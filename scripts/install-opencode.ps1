#Requires -Version 5.1
<#
.SYNOPSIS
    Idempotent installer / verifier for the opencode stack on this Windows host.

.DESCRIPTION
    Installs everything listed in docs/opencode-registry.md, from scratch, and
    checks every step. Re-running it never fails because a step is already done.

    Modes:
      (default)  install whatever is missing, then verify
      -DryRun    print what would be done, change nothing
      -Verify    compare the machine against the registry, change nothing,
                 exit 0 when everything matches, exit 1 on any mismatch

    Guarantees:
      * no secret is stored in this file or written by it
      * no system environment variable is modified (no setx)
      * existing opencode config files are never overwritten unless -Force
        (an overwritten file is copied to <name>.bak-<yyyyMMdd-HHmmss> first)
      * an already installed opencode is never downgraded silently
      * the running opencode server is never stopped or restarted
      * the plugin dependencies are installed into %USERPROFILE%\.config\opencode
        and never into %USERPROFILE% itself; the result is verified afterwards
        and anything that lands in the home directory is removed again
      * every generated config file is parsed back with ConvertFrom-Json before
        it is written, so a broken escape or a malformed plugin entry can never
        reach the disk
      * -Verify prints the measured fact next to the expected value; a version
        that differs from the registry is a WARN with both numbers, never a
        silent [ OK ]

    Exit codes: 0 = ok, 1 = a required item is missing or differs from the
    registry. Advisories (deprecated keys, missing auth.json) are warnings and
    do not change the exit code.

.NOTES
    Russian explanations live in docs/opencode-registry.md.
    This file is deliberately pure ASCII: it travels over ssh, where a
    non-ASCII byte in a .ps1 turns into a ParserError.
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Verify,
    [switch]$Force,
    [string]$OpenCodeVersion = '2.2.4',
    [switch]$AllowLatestOpenCode
)

$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------
# Registry (mirrors docs/opencode-registry.md)
# --------------------------------------------------------------------------
$Registry = [ordered]@{
    ScoopVersion          = '0.6.0'
    OpenCodeVersion       = $OpenCodeVersion
    BrowserControlVersion = '0.8.4'
    PluginPackage         = 'oh-my-opencode-slim'
    PluginVersion         = '3.0.5'
    NodeVersion           = '26.13.0'
    BunVersion            = '1.4.4'
    GitVersion            = '2.56.0.4'
    PythonVersion         = '3.15.2'
    Python312Version      = '3.12.10'
    LazyGitVersion        = '0.66.2'
    UvVersion             = '0.13.6'
    ProxyUrl              = 'http://127.0.0.1:10808'
    NoProxyValue          = 'localhost,127.0.0.1,::1,192.168.1.0/24,100.64.0.0/10,.local,.zeroq.su,.su'
    DefaultModel          = 'opencode-go/deepseek-v4.1-flash'
}

$BucketUrls = [ordered]@{
    'main'     = 'https://github.com/ScoopInstaller/Main.git'
    'extras'   = 'https://github.com/ScoopInstaller/Extras'
    'versions' = 'https://github.com/ScoopInstaller/Versions'
    'winos'    = 'https://github.com/oqyude/winos'
}

# Apps installed through scoop.
$ScoopApps = [ordered]@{
    'git'       = @{ Bucket = 'main';     Version = $Registry.GitVersion }
    'nodejs'    = @{ Bucket = 'main';     Version = $Registry.NodeVersion }
    'bun'       = @{ Bucket = 'main';     Version = $Registry.BunVersion }
    'python'    = @{ Bucket = 'main';     Version = $Registry.PythonVersion }
    'python312' = @{ Bucket = 'versions'; Version = $Registry.Python312Version }
    'lazygit'   = @{ Bucket = 'extras';   Version = $Registry.LazyGitVersion }
    'uv'        = @{ Bucket = 'main';     Version = $Registry.UvVersion }
}

$ScoopRoot = Join-Path $env:USERPROFILE 'scoop'
$ShimsDir  = Join-Path $ScoopRoot 'shims'
$ConfigDir = Join-Path $env:USERPROFILE '.config\opencode'
$DataDir   = Join-Path $env:USERPROFILE '.local\share\opencode'
$LogDir    = Join-Path $DataDir 'log'
$ServeSh   = Join-Path $env:USERPROFILE 'opencode-serve.sh'
$ComputerUseDir = 'C:\Tools\opencode-computer-use'
$HomeDir   = $env:USERPROFILE
$ToolsDir  = 'C:\Tools'

# The plugin spec as it is written into the config files.
$PluginSpec = "$($Registry.PluginPackage)@$($Registry.PluginVersion)"

# --------------------------------------------------------------------------
# Output helpers
# --------------------------------------------------------------------------
function Write-Head($text)  { Write-Host ''; Write-Host "== $text" -ForegroundColor Cyan }
function Write-Ok($text)    { Write-Host "  [ OK ] $text" -ForegroundColor Green }
function Write-Note($text)  { Write-Host "  [ .. ] $text" -ForegroundColor DarkGray }
function Write-Warn2($text) { Write-Host "  [WARN] $text" -ForegroundColor Yellow }
function Write-Fail($text)  { Write-Host "  [FAIL] $text" -ForegroundColor Red }
function Write-Plan($text)  { Write-Host "  [PLAN] $text" -ForegroundColor Cyan }

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
function Ensure-ScoopOnPath {
    if ($env:PATH -notlike "*$ShimsDir*") {
        $env:PATH = "$ShimsDir;$env:PATH"
    }
}

function ConvertTo-CommandLineArgument {
    # Quote a single argument the way the Windows command line expects it.
    param([string]$Arg)
    if ($Arg -notmatch '[\s"]') { return $Arg }
    $escaped = $Arg -replace '(\\*)"', '$1$1\"'
    $escaped = $escaped -replace '(\\*)$', '$1$1'
    return '"' + $escaped + '"'
}

function Resolve-NativeCommand {
    # scoop and npm are shipped as PowerShell shims (shims\npm.ps1), not as
    # executables. Start-Process cannot start a .ps1, so the caller has to
    # know what it is dealing with.
    param([string]$Exe)
    $cmd = Get-Command $Exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd) { return $null }
    $path = [string]$cmd.Source
    if (-not $path) { $path = [string]$cmd.Path }
    if (-not $path) { return $null }
    $ext = [System.IO.Path]::GetExtension($path)
    return [pscustomobject]@{
        Path      = $path
        Extension = $(if ($ext) { $ext.ToLowerInvariant() } else { '' })
    }
}

function Invoke-Native {
    # Runs a native command and returns its exit code and output.
    #
    # The command runs in its own process with redirected pipes: the caller
    # gets a bounded call (a hanging `opencode models` must not block the
    # whole script) and the output is captured as text. Start-Process with
    # file redirection is not used on purpose - its exit code and its
    # redirection files are unreliable here.
    param(
        [string]$Exe,
        [string[]]$Arguments,
        [int]$TimeoutSec = 0,
        [string]$WorkingDirectory
    )
    $argLine = ($Arguments | ForEach-Object { ConvertTo-CommandLineArgument -Arg $_ }) -join ' '
    $resolved = Resolve-NativeCommand -Exe $Exe
    $file = $Exe
    if ($resolved) {
        if ($resolved.Extension -eq '.ps1') {
            # scoop and npm are PowerShell shims - they cannot be started
            # directly, they need a PowerShell host.
            $file = 'powershell.exe'
            $argLine = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" {1}' -f $resolved.Path, $argLine
        } elseif ($resolved.Extension -eq '.cmd' -or $resolved.Extension -eq '.bat') {
            $file = $env:ComSpec
            $argLine = '/d /s /c ""{0}" {1}"' -f $resolved.Path, $argLine
        } else {
            $file = $resolved.Path
        }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $file
    $psi.Arguments = $argLine
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    try {
        [void]$proc.Start()
    } catch {
        return [pscustomobject]@{ ExitCode = -1; Output = $_.Exception.Message; TimedOut = $false }
    }
    # Read both pipes asynchronously, otherwise a chatty child fills the pipe
    # buffer and deadlocks while we wait for the exit.
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    $timedOut = $false
    if ($TimeoutSec -gt 0) {
        if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
            $timedOut = $true
            try { $proc.Kill() } catch { }
        }
    }
    $out = ''
    $err = ''
    try { $out = $outTask.Result } catch { }
    try { $err = $errTask.Result } catch { }
    $code = -1
    try { $code = $proc.ExitCode } catch { }
    $proc.Dispose()

    return [pscustomobject]@{
        ExitCode = $code
        Output   = ($out + $err)
        TimedOut = $timedOut
    }
}

function Get-ScoopAppVersion {
    param([string]$App)
    $current = Join-Path $ScoopRoot "apps\$App\current"
    if (-not (Test-Path -LiteralPath $current)) { return $null }
    $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
    if ($item) {
        $target = $item.Target
        if ($target) {
            $leaf = Split-Path -Leaf ($target | Select-Object -First 1)
            if ($leaf) { return $leaf }
        }
    }
    # Fall back to the highest version directory present.
    $dirs = Get-ChildItem -LiteralPath (Join-Path $ScoopRoot "apps\$App") -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'current' } | Select-Object -ExpandProperty Name
    if ($dirs) {
        return ($dirs | Sort-Object { try { [version]$_ } catch { [version]'0.0' } } -Descending)[0]
    }
    return $null
}

function Get-BucketDir {
    param([string]$Name)
    return (Join-Path $ScoopRoot "buckets\$Name")
}

function Get-BucketManifestVersion {
    # The version the bucket manifest in the local clone points at.
    param([string]$Bucket, [string]$App)
    $manifest = Join-Path (Get-BucketDir -Name $Bucket) "bucket\$App.json"
    if (-not (Test-Path -LiteralPath $manifest)) { return $null }
    try {
        $j = Get-Content -Raw -LiteralPath $manifest | ConvertFrom-Json -ErrorAction Stop
        if ($j -and $j.version) { return [string]$j.version }
    } catch { }
    return $null
}

function Find-BucketManifestCommit {
    # Looks for a bucket commit whose manifest carries the wanted version.
    # The git commands MUST run inside the bucket clone - running them in the
    # current directory is what made the pin lookup fail silently before.
    param([string]$Bucket, [string]$App, [string]$Version)
    $dir = Get-BucketDir -Name $Bucket
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    $sha = Invoke-Native 'git' @('log', '--format=%H', '-n', '40', '--', "bucket/$App.json") `
              -WorkingDirectory $dir -TimeoutSec 120
    if ($sha.ExitCode -ne 0) { return $null }
    foreach ($line in ($sha.Output -split "`r?`n")) {
        $c = $line.Trim()
        if (-not $c) { continue }
        $probe = Invoke-Native 'git' @('show', "${c}:bucket/$App.json") -WorkingDirectory $dir -TimeoutSec 60
        if ($probe.ExitCode -eq 0 -and
            $probe.Output -match ('"version"\s*:\s*"' + [regex]::Escape($Version) + '"')) {
            return $c
        }
    }
    return $null
}

function Test-ScoopBucket {
    param([string]$Name)
    # A bucket is a git clone in scoop\buckets\<name>. The clone is the fact -
    # the `scoop bucket list` table depends on the console it runs in and is
    # empty when scoop has no console at all.
    $dir = Get-BucketDir -Name $Name
    if (-not (Test-Path -LiteralPath $dir)) { return $false }
    return (Test-Path -LiteralPath (Join-Path $dir 'bucket'))
}

function Get-NpmGlobalPackage {
    param([string]$Name)
    $res = Invoke-Native 'npm' @('ls', '-g', '--depth=0', '--json') -TimeoutSec 180
    if ($res.ExitCode -eq 0) {
        $json = ConvertFrom-JsonText -Text $res.Output
        if ($json -and $json.dependencies -and ($json.dependencies.PSObject.Properties.Name -contains $Name)) {
            return $json.dependencies.$Name.version
        }
    }
    # Fallback: read the global root directly.
    $root = Invoke-Native 'npm' @('root', '-g') -TimeoutSec 120
    if ($root.ExitCode -eq 0) {
        $dir = (($root.Output -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1))
        if ($dir) {
            $v = Get-JsonFileField -Path (Join-Path (Join-Path $dir.Trim() $Name) 'package.json') -Field 'version'
            if ($v) { return $v }
        }
    }
    return $null
}

function Get-EnvVarAnyScope {
    param([string]$Name)
    foreach ($scope in @('Process', 'User', 'Machine')) {
        $v = [Environment]::GetEnvironmentVariable($Name, $scope)
        if ($v) { return [pscustomobject]@{ Value = $v; Scope = $scope } }
    }
    return $null
}

function Write-TextFile {
    param([string]$Path, [string]$Content)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Get-JsonFileField {
    param([string]$Path, [string]$Field)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { $j = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
    if ($null -eq $j) { return $null }
    $prop = $j.PSObject.Properties[$Field]
    if ($prop) { return $prop.Value }
    return $null
}

function ConvertFrom-JsonText {
    # Parses JSON out of a command output that may carry extra lines around
    # the document (npm mixes warnings into stdout).
    param([string]$Text)
    if (-not $Text) { return $null }
    $t = $Text.Trim()
    try { return ($t | ConvertFrom-Json -ErrorAction Stop) } catch { }
    $first = $t.IndexOf('{')
    $last = $t.LastIndexOf('}')
    if ($first -lt 0 -or $last -le $first) { return $null }
    try { return ($t.Substring($first, $last - $first + 1) | ConvertFrom-Json -ErrorAction Stop) } catch { }
    return $null
}

function Get-HomeArtifacts {
    # Files that must never live in %USERPROFILE%: they are the fingerprint of
    # a `bun add` / `npm install` that ran in the wrong working directory.
    param([string]$Root = $HomeDir)
    $names = @('node_modules', 'package.json', 'package-lock.json', 'bun.lock', 'bun.lockb')
    $result = New-Object System.Collections.ArrayList
    foreach ($n in $names) {
        $p = Join-Path $Root $n
        [void]$result.Add([pscustomobject]@{ Name = $n; Path = $p; Exists = (Test-Path -LiteralPath $p) })
    }
    return $result
}

function Remove-HomeArtifact {
    param([string]$Path)
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        return $true
    } catch {
        Write-Warn2 "cannot remove $Path : $($_.Exception.Message)"
        return $false
    }
}

function Get-PluginLog {
    # The newest plugin log is the only proof that the plugin really loaded.
    param([string]$Dir = $LogDir)
    if (-not (Test-Path -LiteralPath $Dir)) { return $null }
    $files = Get-ChildItem -LiteralPath $Dir -Filter 'oh-my-opencode-slim*.log' -File -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending
    if (-not $files) { return $null }
    return $files[0]
}

function Get-PluginLogFacts {
    # tools / agents / skills counters as written by the plugin itself.
    param([string]$Path)
    $facts = @{ Tools = $null; Agents = $null; Skills = $null }
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $facts }
    $text = Get-Content -Raw -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $text) { return $facts }
    if ($text -match 'tools registered\s*\{[^{}]*"count"\s*:\s*(\d+)')      { $facts.Tools = [int]$Matches[1] }
    if ($text -match 'agents registered\s*\{[^{}]*"count"\s*:\s*(\d+)')    { $facts.Agents = [int]$Matches[1] }
    if ($text -match 'skills registered[^{]*\{[^{}]*"count"\s*:\s*(\d+)')   { $facts.Skills = [int]$Matches[1] }
    return $facts
}

# --------------------------------------------------------------------------
# Config objects
#
# The configs are built as ordered hashtables and serialized with
# ConvertTo-Json. That is the only way to guarantee a valid JSON document:
# hand written templates with Windows paths produce invalid escape sequences
# ("C:\Users\..." -> \U is not a legal JSON escape) and a lenient parser
# silently mangles the path. Paths are written with forward slashes, which
# Windows accepts and which need no escaping at all.
# --------------------------------------------------------------------------
function ConvertTo-WinPath {
    param([string]$Path)
    if (-not $Path) { return $Path }
    return ($Path -replace '\\', '/')
}

function Get-NodeBinDir {
    return (Join-Path $env:USERPROFILE 'scoop\apps\nodejs\current')
}

function New-OpenCodeConfigObject {
    $nodeBin = Get-NodeBinDir
    return [ordered]@{
        '$schema' = 'https://opencode.ai/config.json'
        'model'   = $Registry.DefaultModel
        'mcp'     = [ordered]@{
            'servers' = [ordered]@{
                'webpage' = [ordered]@{
                    'type'    = 'local'
                    'command' = @('cmd', '/c', (ConvertTo-WinPath (Join-Path $nodeBin 'npx.cmd')),
                                  '-y', '-p', 'webpage-mcp@latest', 'webpage-mcp-stdio')
                }
                'browser-control' = [ordered]@{
                    'type'    = 'local'
                    'command' = @('cmd', '/c', (ConvertTo-WinPath (Join-Path $nodeBin 'bin\browser-control-mcp.cmd')))
                }
                'computer-use' = [ordered]@{
                    'type'    = 'local'
                    'command' = @((ConvertTo-WinPath (Join-Path $ToolsDir 'opencode-computer-use\.venv\Scripts\python.exe')),
                                  '-m', 'opencode_computer_use')
                    'cwd'     = (ConvertTo-WinPath (Join-Path $ToolsDir 'opencode-computer-use'))
                    'enabled' = $true
                    'timeout' = 60000
                    'environment' = [ordered]@{
                        'COMPUTER_USE_LOG_LEVEL'         = 'INFO'
                        'COMPUTER_USE_SINGLE_MONITOR'    = '0'
                        'COMPUTER_USE_MONITOR'            = '0'
                        'COMPUTER_USE_AUTONOMOUS'         = '0'
                        'COMPUTER_USE_MAX_WIDTH'          = '1920'
                        'COMPUTER_USE_OVERLAY_AUTO'       = '1'
                        'COMPUTER_USE_OVERLAY_IDLE_SEC'   = '10'
                    }
                }
                'genoffice' = [ordered]@{
                    'type'    = 'local'
                    'command' = @('cmd', '/c',
                                  (ConvertTo-WinPath (Join-Path $env:LOCALAPPDATA 'Programs\GenOffice\resources\cli\genoffice.cmd')),
                                  'mcp')
                    'enabled' = $true
                    'timeout' = 120000
                }
            }
        }
        # A bare string in "plugins" is an enablement directive for an already
        # installed plugin. An external package is declared as an object with a
        # "package" field (https://opencode.ai/config.json).
        'plugins'  = @([ordered]@{ 'package' = $PluginSpec })
    }
}

function New-CliConfigObject {
    return [ordered]@{
        '$schema' = 'https://opencode.ai/v2/cli.json'
        'plugins' = @([ordered]@{ 'package' = $PluginSpec })
    }
}

function New-TuiConfigObject {
    # tui.json keeps the divergence with the rest of the machine on purpose:
    # it wants oh-my-openagent@latest, the other configs want the slim plugin.
    # The entry is a string (an enablement directive), so it does not pull a
    # package in - the package itself is not installed on this machine.
    return [ordered]@{
        'plugins' = @('oh-my-openagent@latest')
    }
}

function New-OhMyOpenCodeSlimConfigObject {
    $agents = [ordered]@{}
    foreach ($a in @('orchestrator', 'explorer', 'oracle', 'designer', 'fixer')) {
        $agents[$a] = [ordered]@{ 'model' = $Registry.DefaultModel }
    }
    return [ordered]@{ 'agents' = $agents }
}

function ConvertTo-JsonText {
    # Serializes and immediately parses the result back: ConvertFrom-Json
    # uses Json.NET, which rejects illegal escape sequences. A config that
    # does not survive this round trip is never written to disk.
    param($Object)
    $json = $Object | ConvertTo-Json -Depth 12
    $null = $json | ConvertFrom-Json -ErrorAction Stop
    return $json
}

function Write-JsonConfigFile {
    param([string]$Path, $Object)
    $json = ConvertTo-JsonText -Object $Object
    if (Test-Path -LiteralPath $Path) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backup = "$Path.bak-$stamp"
        Copy-Item -LiteralPath $Path -Destination $backup -Force
        Write-Note "previous $Path copied to $backup"
    }
    Write-TextFile -Path $Path -Content $json
    return $json
}

# --------------------------------------------------------------------------
# Check framework
#
# Every check scriptblock takes one argument: a hashtable of context values.
# The context is stored next to the scriptblock and passed in at call time.
# This avoids PowerShell's late-binding closure behaviour: a scriptblock that
# reads a loop variable directly would see the LAST loop value, not its own.
#
# A Test scriptblock returns one of:
#   $true                     - the item is satisfied
#   $false                    - the item is missing
#   a hashtable               - @{ State = 'ok'|'missing'|'mismatch'|'warn';
#                                  Message = '...'; Expected = '...'; Actual = '...' }
# --------------------------------------------------------------------------
$Checks = New-Object System.Collections.ArrayList

function New-CheckState {
    param(
        [string]$State,
        [string]$Message = '',
        [string]$Expected = '',
        [string]$Actual = ''
    )
    return @{ State = $State; Message = $Message; Expected = $Expected; Actual = $Actual }
}

function Add-Check {
    param(
        [string]$Name,
        [string]$Detail,
        [hashtable]$Context,
        [scriptblock]$Test,     # returns $true / $false / a state hashtable
        [scriptblock]$Install,  # performs the install; $true on success
        [bool]$Required = $true,
        [scriptblock]$Fact      # returns the measured fact as a string
    )
    [void]$Checks.Add([pscustomobject]@{
        Name = $Name; Detail = $Detail; Context = $Context
        Test = $Test; Install = $Install; Required = $Required; Fact = $Fact
    })
}

function Get-StateField {
    # Reads a field from a state hashtable or from a PSCustomObject.
    param($Obj, [string]$Name)
    if ($null -eq $Obj) { return '' }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name)) { return $Obj[$Name] }
        return ''
    }
    $prop = $Obj.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return ''
}

function Invoke-CheckTest {
    param($c)
    $empty = @{ State = 'missing'; Message = ''; Expected = ''; Actual = '' }
    try {
        $r = & $c.Test $c.Context
    } catch {
        $empty.Message = $_.Exception.Message
        return $empty
    }
    if ($null -eq $r) { return $empty }
    if ($r -is [bool]) {
        if ($r) { return @{ State = 'ok'; Message = ''; Expected = ''; Actual = '' } }
        return $empty
    }
    if ($r -is [System.Collections.IDictionary] -or $r -is [pscustomobject]) {
        $state = Get-StateField -Obj $r -Name 'State'
        if (-not $state) { $state = 'ok' }
        return @{
            State    = $state
            Message  = [string](Get-StateField -Obj $r -Name 'Message')
            Expected = [string](Get-StateField -Obj $r -Name 'Expected')
            Actual   = [string](Get-StateField -Obj $r -Name 'Actual')
        }
    }
    return @{ State = 'ok'; Message = ''; Expected = ''; Actual = '' }
}

function Get-CheckFact {
    param($c)
    if (-not $c.Fact) { return '' }
    try {
        $f = & $c.Fact $c.Context
        if ($null -eq $f) { return '' }
        return ([string]$f).Trim()
    } catch {
        return "fact unavailable: $($_.Exception.Message)"
    }
}

# --- 1. scoop ------------------------------------------------------------
Add-Check -Name 'scoop' -Detail "scoop $($Registry.ScoopVersion) in $ScoopRoot" -Context @{} -Required $true -Test {
    param($d)
    (Get-Command scoop -ErrorAction SilentlyContinue) -ne $null
} -Install {
    param($d)
    Write-Note 'installing scoop from https://get.scoop.sh'
    $boot = Join-Path ([System.IO.Path]::GetTempPath()) ("scoop-install-{0}.ps1" -f [guid]::NewGuid().ToString('N'))
    Write-TextFile -Path $boot -Content 'Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force | Out-Null
Invoke-WebRequest https://get.scoop.sh -UseBasicParsing | Invoke-Expression'
    $r = Invoke-Native 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $boot) -TimeoutSec 600
    Remove-Item -LiteralPath $boot -Force -ErrorAction SilentlyContinue
    if ($r.ExitCode -ne 0) { Write-Fail "scoop installer failed: $($r.Output.Trim())"; return $false }
    Ensure-ScoopOnPath
    return ((Get-Command scoop -ErrorAction SilentlyContinue) -ne $null)
} -Fact {
    param($d)
    $cmd = Get-Command scoop -ErrorAction SilentlyContinue
    if (-not $cmd) { return 'not found' }
    $v = (Invoke-Native 'scoop' @('--version') -TimeoutSec 60).Output.Trim()
    return "found: $v"
}

# --- 2. buckets ----------------------------------------------------------
foreach ($b in $BucketUrls.Keys) {
    $bucketName = $b
    $bucketUrl  = $BucketUrls[$b]
    Add-Check -Name "bucket:$bucketName" -Detail "scoop bucket $bucketName <- $bucketUrl" `
        -Context @{ Bucket = $bucketName; Url = $bucketUrl } -Required $true -Test {
        param($d)
        Test-ScoopBucket -Name $d.Bucket
    } -Install {
        param($d)
        $r = Invoke-Native 'scoop' @('bucket', 'add', $d.Bucket, $d.Url) -TimeoutSec 600
        if ($r.ExitCode -ne 0 -and -not (Test-ScoopBucket -Name $d.Bucket)) {
            Write-Fail "scoop bucket add $($d.Bucket) failed: $($r.Output.Trim())"; return $false
        }
        return $true
    } -Fact {
        param($d)
        $dir = Get-BucketDir -Name $d.Bucket
        if (-not (Test-Path -LiteralPath $dir)) { return 'not cloned' }
        $m = Join-Path $dir 'bucket'
        $n = 0
        if (Test-Path -LiteralPath $m) {
            try { $n = [System.IO.Directory]::GetFiles($m, '*.json').Length } catch { $n = 0 }
        }
        return "clone present, $n manifests"
    }
}

# --- 3. scoop apps -------------------------------------------------------
foreach ($app in $ScoopApps.Keys) {
    $appName   = $app
    $appBucket = $ScoopApps[$app].Bucket
    $appWant   = $ScoopApps[$app].Version
    Add-Check -Name "app:$appName" -Detail "scoop $appBucket/$appName $appWant" `
        -Context @{ App = $appName; Bucket = $appBucket; Want = $appWant } -Required $true -Test {
        param($d)
        $v = Get-ScoopAppVersion -App $d.App
        if (-not $v) { return $false }
        if ($v -ne $d.Want) {
            return New-CheckState 'mismatch' 'the installed version differs from the registry' $d.Want $v
        }
        return $true
    } -Install {
        param($d)
        $r = Invoke-Native 'scoop' @('install', "$($d.Bucket)/$($d.App)") -TimeoutSec 1800
        if ($r.ExitCode -ne 0 -and (Get-ScoopAppVersion -App $d.App) -eq $null) {
            Write-Fail "scoop install $($d.Bucket)/$($d.App) failed: $($r.Output.Trim())"; return $false
        }
        $v = Get-ScoopAppVersion -App $d.App
        if ($v -and $v -ne $d.Want) {
            Write-Warn2 "scoop $appName is $v, the registry expects $($d.Want) - run 'scoop update $($d.Bucket)/$($d.App)' to move to it"
        }
        return $true
    } -Fact {
        param($d)
        $v = Get-ScoopAppVersion -App $d.App
        if (-not $v) { return 'not installed' }
        return "installed $v (expected $($d.Want))"
    }
}

# --- 4. opencode ---------------------------------------------------------
Add-Check -Name 'app:opencode2' -Detail "opencode2 $($Registry.OpenCodeVersion) (bucket versions)" `
    -Context @{ Want = $Registry.OpenCodeVersion; Latest = [bool]$AllowLatestOpenCode } -Required $true -Test {
    param($d)
    $v = Get-ScoopAppVersion -App 'opencode2'
    if (-not $v) { return $false }
    if ($v -ne $d.Want) {
        return New-CheckState 'mismatch' 'the installed version differs from the registry' $d.Want $v
    }
    return $true
} -Install {
    param($d)
    $bucketVersion = Get-BucketManifestVersion -Bucket 'versions' -App 'opencode2'
    $target = $d.Want
    if ($d.Latest) { $target = $bucketVersion }

    if ($target -and $bucketVersion -and $target -ne $bucketVersion) {
        # The requested pin is not the manifest the bucket ships. Try to find
        # the pinned manifest in the bucket history before giving up on it.
        $commit = Find-BucketManifestCommit -Bucket 'versions' -App 'opencode2' -Version $target
        if ($commit) {
            $short = $commit.Substring(0, [Math]::Min(10, $commit.Length))
            $manifest = "https://raw.githubusercontent.com/ScoopInstaller/Versions/$short/bucket/opencode2.json"
            Write-Note "installing pinned opencode2 $target from $manifest"
            $r = Invoke-Native 'scoop' @('install', $manifest) -TimeoutSec 1800
            if ($r.ExitCode -ne 0 -and (Get-ScoopAppVersion -App 'opencode2') -ne $target) {
                Write-Fail "scoop install <pinned manifest> failed: $($r.Output.Trim())"
                Write-Warn2 "falling back to the version the bucket ships ($bucketVersion)"
            }
        } else {
            Write-Warn2 "opencode2 $target is not in the versions bucket (it ships $bucketVersion); the pin cannot be installed"
        }
    }

    $target = $bucketVersion
    if (-not $target) { $target = $d.Want }
    $installed = Get-ScoopAppVersion -App 'opencode2'
    if ($installed -and $installed -ne $target) {
        Write-Note "updating opencode2 $installed -> $target"
        $r = Invoke-Native 'scoop' @('update', 'versions/opencode2') -TimeoutSec 1800
        if ($r.ExitCode -ne 0) { Write-Fail "scoop update versions/opencode2 failed: $($r.Output.Trim())" }
    } else {
        $r = Invoke-Native 'scoop' @('install', 'versions/opencode2') -TimeoutSec 1800
        if ($r.ExitCode -ne 0 -and (Get-ScoopAppVersion -App 'opencode2') -eq $null) {
            Write-Fail "scoop install versions/opencode2 failed: $($r.Output.Trim())"; return $false
        }
    }

    $now = Get-ScoopAppVersion -App 'opencode2'
    if (-not $now) { Write-Fail 'opencode2 is still not installed'; return $false }
    if ($now -ne $d.Want) {
        Write-Warn2 "installed opencode2 $now, the registry expects $($d.Want) (bucket ships $bucketVersion)"
    }
    return $true
} -Fact {
    param($d)
    $v = Get-ScoopAppVersion -App 'opencode2'
    $b = Get-BucketManifestVersion -Bucket 'versions' -App 'opencode2'
    if (-not $v) { return "not installed (bucket ships $b)" }
    return "installed $v, bucket ships $b, registry expects $($d.Want)"
}

# --- 5. global npm package ----------------------------------------------
Add-Check -Name 'npm:@opencode-ai/browser-control' `
    -Detail "npm -g @opencode-ai/browser-control@$($Registry.BrowserControlVersion)" `
    -Context @{ Want = $Registry.BrowserControlVersion } -Required $true -Test {
    param($d)
    $v = Get-NpmGlobalPackage -Name '@opencode-ai/browser-control'
    if (-not $v) { return $false }
    if ($v -ne $d.Want) {
        return New-CheckState 'mismatch' 'the installed version differs from the registry' $d.Want $v
    }
    return $true
} -Install {
    param($d)
    $r = Invoke-Native 'npm' @('install', '-g', "@opencode-ai/browser-control@$($d.Want)") -TimeoutSec 900
    if ($r.ExitCode -ne 0 -and (Get-NpmGlobalPackage -Name '@opencode-ai/browser-control') -eq $null) {
        Write-Fail "npm install -g failed: $($r.Output.Trim())"; return $false
    }
    return $true
} -Fact {
    param($d)
    $v = Get-NpmGlobalPackage -Name '@opencode-ai/browser-control'
    if (-not $v) { return 'not installed' }
    return "installed $v (expected $($d.Want))"
}

# --- 6. opencode config files --------------------------------------------
# The shape of a config file is checked in one place (Get-ConfigFileState),
# so that the check and the repair agree on what "broken" means.
function Get-ConfigFileState {
    param([string]$Path, [string]$Kind)
    if (-not (Test-Path -LiteralPath $Path)) {
        return New-CheckState 'missing' 'the file is missing'
    }
    # A strict parse: ConvertFrom-Json (Json.NET) rejects illegal escapes,
    # so a config with a broken Windows path can never pass here.
    try {
        $j = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return New-CheckState 'missing' "not valid JSON: $($_.Exception.Message)"
    }
    if ($Kind -eq 'opencode' -or $Kind -eq 'cli') {
        $entries = @($j.plugins | Where-Object { $_ })
        $pkg = @($entries | Where-Object { $_.PSObject.Properties['package'] })
        if ($pkg.Count -eq 0) {
            return New-CheckState 'missing' 'plugins does not declare the package as { "package": "..." }'
        }
        if ($pkg[0].package -ne $PluginSpec) {
            return New-CheckState 'mismatch' 'the declared plugin package differs from the registry' $PluginSpec $pkg[0].package
        }
        if ($j.PSObject.Properties['plugin']) {
            return New-CheckState 'warn' 'the deprecated "plugin" key (singular) is present'
        }
    }
    if ($Kind -eq 'opencode') {
        $cmd = @($j.mcp.servers.webpage.command | Where-Object { $_ })
        $npx = (ConvertTo-WinPath (Join-Path (Get-NodeBinDir) 'npx.cmd'))
        # opencode itself rewrites this command (it normalizes the path to
        # "npx"), so both the full path and the bare name are accepted.
        if ($cmd.Count -lt 3 -or ($cmd[2] -ne $npx -and $cmd[2] -ne 'npx' -and $cmd[2] -ne 'npx.cmd')) {
            return New-CheckState 'missing' "the webpage command does not start npx: $($cmd -join ' ')"
        }
    }
    if ($Kind -eq 'tui') {
        $entries = @($j.plugins | Where-Object { $_ })
        if ($entries.Count -eq 0 -and $j.PSObject.Properties['plugin']) { $entries = @($j.plugin | Where-Object { $_ }) }
        if (@($entries | Where-Object { $_ -eq 'oh-my-openagent@latest' }).Count -eq 0) {
            return New-CheckState 'missing' 'oh-my-openagent@latest is not declared'
        }
        if ($j.PSObject.Properties['plugin']) {
            return New-CheckState 'warn' 'the deprecated "plugin" key (singular) is present - migrate it to "plugins"'
        }
    }
    if ($Kind -eq 'agents') {
        foreach ($a in @('orchestrator', 'explorer', 'oracle', 'designer', 'fixer')) {
            if (-not $j.agents.PSObject.Properties[$a]) {
                return New-CheckState 'missing' "the agent $a is not bound"
            }
        }
    }
    return New-CheckState 'ok'
}

$ConfigFiles = @(
    @{ File = 'opencode.jsonc';           Kind = 'opencode' },
    @{ File = 'cli.json';                 Kind = 'cli' },
    @{ File = 'tui.json';                 Kind = 'tui' },
    @{ File = 'oh-my-opencode-slim.json'; Kind = 'agents' }
)
foreach ($cf in $ConfigFiles) {
    $cfgFile = $cf.File
    $cfgKind = $cf.Kind
    Add-Check -Name "config:$cfgFile" -Detail "$ConfigDir\$cfgFile" `
        -Context @{ File = $cfgFile; Kind = $cfgKind } -Required $true -Test {
        param($d)
        $p = Join-Path $ConfigDir $d.File
        $state = Get-ConfigFileState -Path $p -Kind $d.Kind
        if ($state.State -eq 'ok') { return $true }
        return $state
    } -Install {
        param($d)
        $p = Join-Path $ConfigDir $d.File
        $exists = Test-Path -LiteralPath $p
        if ($exists -and -not $Force) {
            $state = Get-ConfigFileState -Path $p -Kind $d.Kind
            if ($state.State -eq 'ok' -or $state.State -eq 'warn') {
                Write-Warn2 "$($d.File) exists and is left untouched (use -Force to rewrite it)"
                return $true
            }
            # The file is broken (not valid JSON, or the plugin entry has the
            # wrong form). Such a file is repaired, the old one is kept as a
            # .bak-<timestamp> copy.
            Write-Warn2 "$($d.File) is broken ($($state.Message)) - rewriting it"
        }
        Write-Note "writing $p"
        switch ($d.Kind) {
            'opencode' { $null = Write-JsonConfigFile -Path $p -Object (New-OpenCodeConfigObject) }
            'cli'      { $null = Write-JsonConfigFile -Path $p -Object (New-CliConfigObject) }
            'tui'      { $null = Write-JsonConfigFile -Path $p -Object (New-TuiConfigObject) }
            'agents'   { $null = Write-JsonConfigFile -Path $p -Object (New-OhMyOpenCodeSlimConfigObject) }
        }
        # read it back: a config that does not parse is a broken config
        try {
            $null = Get-Content -Raw -LiteralPath $p | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Fail "$($d.File) is not valid JSON after writing: $($_.Exception.Message)"
            return $false
        }
        return $true
    } -Fact {
        param($d)
        $p = Join-Path $ConfigDir $d.File
        if (-not (Test-Path -LiteralPath $p)) { return 'missing' }
        try {
            $j = Get-Content -Raw -LiteralPath $p | ConvertFrom-Json -ErrorAction Stop
        } catch {
            return 'not valid JSON'
        }
        $bits = @('strict JSON ok')
        if ($j.PSObject.Properties['plugins']) {
            $parts = @()
            foreach ($e in @($j.plugins)) {
                if (-not $e) { continue }
                if ($e -is [string]) { $parts += $e }
                elseif ($e.PSObject.Properties['package']) { $parts += "{package: $($e.package)}" }
            }
            $bits += ('plugins: ' + ($parts -join ', '))
        }
        if ($j.PSObject.Properties['mcp']) {
            $bits += ('servers: ' + (($j.mcp.servers.PSObject.Properties.Name) -join ', '))
        }
        return ($bits -join ' | ')
    }
}

# --- 7. plugin dependencies ----------------------------------------------
# The config only DECLARES the plugin. opencode loads a plugin from the
# node_modules of the config directory, so the dependencies have to be
# materialized there - otherwise the plugin is silently ignored.
Add-Check -Name "plugin:$($Registry.PluginPackage)" `
    -Detail "bun add $PluginSpec in $ConfigDir" `
    -Context @{ Package = $Registry.PluginPackage; Version = $Registry.PluginVersion; Spec = $PluginSpec } `
    -Required $true -Test {
    param($d)
    $dir = Join-Path $ConfigDir "node_modules\$($d.Package)"
    if (-not (Test-Path -LiteralPath $dir)) { return $false }
    $v = Get-JsonFileField -Path (Join-Path $dir 'package.json') -Field 'version'
    if (-not $v) { return New-CheckState 'missing' 'node_modules exists but the package.json is unreadable' }
    if ($v -ne $d.Version) {
        return New-CheckState 'mismatch' "installed plugin is $v, registry expects $($d.Version)" $d.Version $v
    }
    return $true
} -Install {
    param($d)
    if (-not (Test-Path -LiteralPath $ConfigDir)) {
        New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    }
    if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
        Write-Fail 'bun is not on PATH - the plugin dependencies cannot be installed'
        return $false
    }
    # Remember what the home directory looks like: a `bun add` that runs in
    # the wrong directory drops node_modules and package.json into $HOME.
    $before = Get-HomeArtifacts
    Write-Note "bun add $($d.Spec) (working directory: $ConfigDir)"
    # The working directory is passed explicitly: `bun add` without it drops
    # node_modules and package.json into $HOME.
    $r = Invoke-Native 'bun' @('add', $d.Spec) -TimeoutSec 1800 -WorkingDirectory $ConfigDir
    if ($r.ExitCode -ne 0) {
        Write-Fail "bun add $($d.Spec) failed: $($r.Output.Trim())"
        return $false
    }
    $dir = Join-Path $ConfigDir "node_modules\$($d.Package)"
    if (-not (Test-Path -LiteralPath $dir)) {
        Write-Fail "node_modules\$($d.Package) is missing in $ConfigDir after 'bun add'"
        Write-Fail "the install did not land in the config directory"
        return $false
    }
    # Nothing may stay in the home directory.
    $after = Get-HomeArtifacts
    foreach ($a in $after) {
        $wasThere = ($before | Where-Object { $_.Name -eq $a.Name }).Exists
        if ($a.Exists -and -not $wasThere) {
            Write-Warn2 "$($a.Path) was created outside the config directory - removing it"
            Remove-HomeArtifact -Path $a.Path | Out-Null
        }
    }
    return $true
} -Fact {
    param($d)
    $dir = Join-Path $ConfigDir "node_modules\$($d.Package)"
    if (-not (Test-Path -LiteralPath $dir)) { return 'node_modules missing' }
    $v = Get-JsonFileField -Path (Join-Path $dir 'package.json') -Field 'version'
    $declared = Get-JsonFileField -Path (Join-Path $ConfigDir 'package.json') -Field 'dependencies'
    $inPkg = $false
    if ($declared) {
        $prop = $declared.PSObject.Properties[$d.Package]
        if ($prop) { $inPkg = $true }
    }
    return "node_modules present, version $v, declared in the config package.json: $inPkg"
}

# --- 8. the plugin is alive (log proof) ----------------------------------
Add-Check -Name "plugin-live:$($Registry.PluginPackage)" `
    -Detail 'the plugin log must contain "tools registered"' `
    -Context @{ Dir = $LogDir } -Required $true -Test {
    param($d)
    $log = Get-PluginLog -Dir $d.Dir
    if (-not $log) {
        return New-CheckState 'missing' "no plugin log in $($d.Dir) - start opencode once, the log is written on the first load"
    }
    $facts = Get-PluginLogFacts -Path $log.FullName
    if (-not $facts.Tools) {
        return New-CheckState 'missing' "the plugin log $($log.Name) has no 'tools registered' line"
    }
    return $true
} -Fact {
    param($d)
    $log = Get-PluginLog -Dir $d.Dir
    if (-not $log) { return 'no plugin log' }
    $facts = Get-PluginLogFacts -Path $log.FullName
    return "tools=$($facts.Tools) agents=$($facts.Agents) skills=$($facts.Skills) (log $($log.Name))"
}

# --- 9. the home directory stays clean -----------------------------------
Add-Check -Name 'home:hygiene' `
    -Detail "$HomeDir must not contain node_modules / package.json / bun.lock" `
    -Context @{} -Required $true -Test {
    param($d)
    $stray = @(Get-HomeArtifacts | Where-Object { $_.Exists })
    if ($stray.Count -eq 0) { return $true }
    return New-CheckState 'missing' ("stray: " + (($stray | ForEach-Object { $_.Name }) -join ', '))
} -Install {
    param($d)
    $stray = @(Get-HomeArtifacts | Where-Object { $_.Exists })
    if ($stray.Count -eq 0) { return $true }
    foreach ($s in $stray) {
        if ($s.Name -like 'bun.lock*') {
            # An orphaned lock file of a `bun add` that ran in $HOME. Without a
            # package.json next to it it is pure garbage - remove it.
            Write-Warn2 "removing the orphaned $($s.Path)"
            Remove-HomeArtifact -Path $s.Path | Out-Null
        } else {
            Write-Warn2 "$($s.Path) is not managed by this installer - remove it by hand"
        }
    }
    return $true
} -Fact {
    param($d)
    $stray = @(Get-HomeArtifacts | Where-Object { $_.Exists })
    if ($stray.Count -eq 0) { return 'clean' }
    return ('stray: ' + (($stray | ForEach-Object { $_.Name }) -join ', '))
}

# --- 10. computer-use venv ------------------------------------------------
Add-Check -Name 'venv:computer-use' -Detail "$ComputerUseDir\.venv (python -m opencode_computer_use)" `
    -Context @{ Dir = $ComputerUseDir } -Required $true -Test {
    param($d)
    $py = Join-Path $d.Dir '.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $py)) { return $false }
    $r = Invoke-Native $py @('-c', 'import opencode_computer_use') -TimeoutSec 120
    return ($r.ExitCode -eq 0)
} -Install {
    param($d)
    $py = Join-Path $d.Dir '.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $py)) {
        Write-Warn2 "no venv at $($d.Dir)\.venv - it is built from the upstream checkout:"
        Write-Warn2 '  git clone https://github.com/rwarx/opencode-computer-use C:\Tools\opencode-computer-use'
        Write-Warn2 '  uv venv C:\Tools\opencode-computer-use\.venv --python 3.12'
        Write-Warn2 '  uv pip install -e "C:\Tools\opencode-computer-use[all]"'
        return $false
    }
    $r = Invoke-Native $py @('-c', 'import opencode_computer_use') -TimeoutSec 120
    return ($r.ExitCode -eq 0)
} -Fact {
    param($d)
    $py = Join-Path $d.Dir '.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $py)) { return 'no venv' }
    $r = Invoke-Native $py @('-c', 'import opencode_computer_use') -TimeoutSec 120
    if ($r.ExitCode -eq 0) { return 'venv present, opencode_computer_use importable' }
    return "venv present, but the import fails (exit $($r.ExitCode))"
}

# --- 11. egress proxy (report only, never setx) ---------------------------
Add-Check -Name 'env:proxy' `
    -Detail "HTTP_PROXY / HTTPS_PROXY = $($Registry.ProxyUrl); NO_PROXY = $($Registry.NoProxyValue)" `
    -Context @{ Url = $Registry.ProxyUrl; NoProxy = $Registry.NoProxyValue; ServeSh = $ServeSh } -Required $true -Test {
    param($d)
    $h = Get-EnvVarAnyScope 'HTTP_PROXY'
    $s = Get-EnvVarAnyScope 'HTTPS_PROXY'
    $n = Get-EnvVarAnyScope 'NO_PROXY'
    if ($h -and $s -and $n) { return $true }
    # The proxy may also be exported inside the server launcher.
    if ((Test-Path -LiteralPath $d.ServeSh) -and
        ((Get-Content -Raw -LiteralPath $d.ServeSh) -match 'HTTP_PROXY') -and
        ((Get-Content -Raw -LiteralPath $d.ServeSh) -match 'NO_PROXY')) { return $true }
    return $false
} -Install {
    param($d)
    Write-Warn2 'the egress proxy is missing from the environment.'
    Write-Warn2 'opencode cannot load the provider config without it:'
    Write-Warn2 '  GET https://opencode.ai/console/api/v2/config -> ECONNRESET'
    Write-Warn2 'the provider opencode-go is then absent from the registry and'
    Write-Warn2 "the default model $($Registry.DefaultModel) is unavailable."
    Write-Warn2 'Set these BEFORE starting the server (this script never runs setx):'
    Write-Warn2 "  export HTTP_PROXY=$($d.Url)"
    Write-Warn2 "  export HTTPS_PROXY=$($d.Url)"
    Write-Warn2 "  export NO_PROXY=$($d.NoProxy)"
    Write-Warn2 '  for a Windows session: setx HTTP_PROXY "URL" / setx NO_PROXY "LIST"'
    return $false
} -Fact {
    param($d)
    $h = Get-EnvVarAnyScope 'HTTP_PROXY'
    $s = Get-EnvVarAnyScope 'HTTPS_PROXY'
    $n = Get-EnvVarAnyScope 'NO_PROXY'
    if ($h -and $s -and $n) {
        return "HTTP_PROXY=$($h.Value) [$($h.Scope)], HTTPS_PROXY=$($s.Value) [$($s.Scope)], NO_PROXY=$($n.Value) [$($n.Scope)]"
    }
    if ((Test-Path -LiteralPath $d.ServeSh) -and
        ((Get-Content -Raw -LiteralPath $d.ServeSh) -match 'HTTP_PROXY')) {
        return 'not in the environment - the launcher script exports it instead'
    }
    return 'not in the environment'
}

# --- 12. auth (report only) ------------------------------------------------
Add-Check -Name 'auth:login' `
    -Detail 'opencode auth list - logins are redone, auth.json is NOT migrated' `
    -Context @{ DataDir = $DataDir } -Required $false -Test {
    param($d)
    $p = Join-Path $d.DataDir 'auth.json'
    if (-not (Test-Path -LiteralPath $p)) { return $false }
    $r = Invoke-Native 'opencode' @('auth', 'list') -TimeoutSec 120
    return ($r.ExitCode -eq 0)
} -Install {
    param($d)
    Write-Warn2 'no usable auth.json / opencode auth list failed.'
    Write-Warn2 'auth.json is not migrated by design - run:  opencode auth login'
    Write-Warn2 'The OpenCode Console account lives in opencode.db (table credential),'
    Write-Warn2 'so either carry opencode.db over or log in again.'
    return $false
} -Fact {
    param($d)
    $p = Join-Path $d.DataDir 'auth.json'
    if (-not (Test-Path -LiteralPath $p)) { return 'auth.json missing' }
    $r = Invoke-Native 'opencode' @('auth', 'list') -TimeoutSec 120
    return "auth.json present, opencode auth list exit $($r.ExitCode)"
}

# --- 13. serve launcher (report only) -------------------------------------
Add-Check -Name 'launcher:opencode-serve.sh' -Detail "$ServeSh (starts opencode serve on :4096)" `
    -Context @{ ServeSh = $ServeSh } -Required $false -Test {
    param($d)
    (Test-Path -LiteralPath $d.ServeSh) -and
    ((Get-Content -Raw -LiteralPath $d.ServeSh) -match 'opencode(.exe)?\s+serve')
} -Install {
    param($d)
    Write-Warn2 "$($d.ServeSh) is missing or does not start 'opencode serve'."
    Write-Warn2 'Without it the server on port 4096 does not come up.'
    return $false
} -Fact {
    param($d)
    if (-not (Test-Path -LiteralPath $d.ServeSh)) { return 'missing' }
    if ((Get-Content -Raw -LiteralPath $d.ServeSh) -match 'opencode(.exe)?\s+serve') { return 'starts opencode serve' }
    return 'does not start opencode serve'
}

# --------------------------------------------------------------------------
# Run
# --------------------------------------------------------------------------
Ensure-ScoopOnPath
$exitCode = 0
$failures = New-Object System.Collections.ArrayList
$mismatches = New-Object System.Collections.ArrayList
$warnings = New-Object System.Collections.ArrayList

if ($Verify) {
    Write-Head 'VERIFY (read only)'
    foreach ($c in $Checks) {
        $state = Invoke-CheckTest $c
        $fact = Get-CheckFact $c
        $label = "$($c.Name) - $($c.Detail)"
        if ($fact) { $label = "$label | $fact" }
        switch ($state.State) {
            'ok' {
                Write-Ok $label
            }
            'mismatch' {
                $msg = if ($state.Message) { $state.Message } else { "expected $($state.Expected), actual $($state.Actual)" }
                Write-Warn2 "$label | $msg"
                [void]$mismatches.Add("$($c.Name): $msg")
            }
            'warn' {
                $msg = if ($state.Message) { $state.Message } else { 'warning' }
                Write-Warn2 "$label | $msg"
                [void]$warnings.Add("$($c.Name): $msg")
            }
            default {
                $msg = if ($state.Message) { $state.Message } else { 'missing' }
                if ($c.Required) {
                    Write-Fail "$label | $msg"
                    [void]$failures.Add($c.Name)
                } else {
                    Write-Warn2 "$label | $msg"
                }
            }
        }
    }

    # Advisory checks that need the network: informational only.
    Write-Head 'ADVISORY'
    $models = Invoke-Native 'opencode' @('models') -TimeoutSec 90
    if ($models.TimedOut) {
        Write-Warn2 'opencode models timed out after 90s - the provider registry did not load (or the egress proxy is missing)'
    } elseif ($models.ExitCode -ne 0) {
        Write-Warn2 'opencode models failed - the provider registry did not load'
    } else {
        $goCount = ([regex]::Matches($models.Output, '(?m)^opencode-go/')).Count
        if ($goCount -gt 0) {
            Write-Ok "provider opencode-go is present in the registry ($goCount models)"
        } else {
            Write-Warn2 'provider opencode-go is absent from the registry - check the egress proxy (docs/opencode-registry.md section 0.1)'
        }
        if ($models.Output -match [regex]::Escape($Registry.DefaultModel)) {
            Write-Ok "the default model $($Registry.DefaultModel) resolves"
        } else {
            Write-Warn2 "the default model $($Registry.DefaultModel) does not resolve - decide explicitly on reinstall (section 0.3)"
        }
    }
    $tuiPath  = Join-Path $ConfigDir 'tui.json'
    $mainPath = Join-Path $ConfigDir 'opencode.jsonc'
    if ((Test-Path -LiteralPath $tuiPath) -and (Test-Path -LiteralPath $mainPath)) {
        $tuiPlug  = Get-Content -Raw -LiteralPath $tuiPath
        $mainPlug = Get-Content -Raw -LiteralPath $mainPath
        if (($tuiPlug -match 'oh-my-openagent') -and ($mainPlug -match 'oh-my-opencode-slim')) {
            Write-Warn2 'plugin divergence kept as is: tui.json wants oh-my-openagent@latest, opencode.jsonc and cli.json want oh-my-opencode-slim@3.0.5'
        }
    }

    Write-Head 'PLUGIN'
    $log = Get-PluginLog -Dir $LogDir
    if ($log) {
        $facts = Get-PluginLogFacts -Path $log.FullName
        Write-Note "log: $($log.FullName) ($($log.LastWriteTime))"
        if ($facts.Tools) { Write-Ok "tools registered: $($facts.Tools)" } else { Write-Fail 'tools registered: not found in the log' }
        if ($facts.Agents) { Write-Ok "agents registered: $($facts.Agents)" } else { Write-Warn2 'agents registered: not found in the log' }
        if ($facts.Skills) { Write-Ok "skills registered: $($facts.Skills)" } else { Write-Warn2 'skills registered: not found in the log' }
    } else {
        Write-Fail "no plugin log in $LogDir - start opencode once so the plugin loads"
    }

    Write-Head 'RESULT'
    if ($warnings.Count -gt 0) {
        Write-Warn2 ("warnings: " + ($warnings -join '; '))
    }
    if ($mismatches.Count -gt 0) {
        Write-Warn2 ("mismatched: " + ($mismatches -join '; '))
    }
    if ($failures.Count -eq 0 -and $mismatches.Count -eq 0) {
        Write-Ok 'all required items match the registry'
    } else {
        if ($failures.Count -gt 0) { Write-Fail ("missing: " + ($failures -join ', ')) }
        $exitCode = 1
    }
    exit $exitCode
}

if ($DryRun) {
    Write-Head 'DRY RUN (nothing is changed)'
    foreach ($c in $Checks) {
        $state = Invoke-CheckTest $c
        $fact = Get-CheckFact $c
        $label = "$($c.Name) - $($c.Detail)"
        if ($fact) { $label = "$label | $fact" }
        if ($state.State -eq 'ok') {
            Write-Ok ("already done: $label")
        } elseif ($state.State -eq 'mismatch' -or $state.State -eq 'warn') {
            Write-Warn2 ("would check: $label | $($state.Message)")
        } else {
            Write-Plan ("would do: $label")
        }
    }
    Write-Head 'RESULT'
    Write-Note 'dry run finished, nothing was changed'
    exit 0
}

Write-Head 'INSTALL'
foreach ($c in $Checks) {
    $state = Invoke-CheckTest $c
    if ($state.State -eq 'ok') {
        Write-Ok ("already done: $($c.Name)")
        continue
    }
    Write-Note ("installing: $($c.Name) - $($c.Detail)")
    $done = $false
    try { $done = [bool](& $c.Install $c.Context) } catch {
        Write-Fail ("$($c.Name) threw: $($_.Exception.Message)")
        $done = $false
    }
    if ($done) {
        Write-Ok ("done: $($c.Name)")
    } elseif ($c.Required) {
        Write-Fail ("FAILED: $($c.Name)")
        [void]$failures.Add($c.Name)
    } else {
        Write-Warn2 ("not done (advisory): $($c.Name)")
    }
}

Write-Head 'RESULT'
if ($failures.Count -eq 0) {
    Write-Ok 'installation finished without failures'
    Write-Note 'remaining manual steps:'
    Write-Note '  1. export HTTP_PROXY / HTTPS_PROXY / NO_PROXY for the server environment'
    Write-Note '  2. opencode auth login   (auth.json is not migrated)'
    Write-Note '  3. start opencode once - the plugin log is written on the first load'
    Write-Note '  4. decide the default model (docs/opencode-registry.md section 0.3)'
} else {
    Write-Fail ("failed items: " + ($failures -join ', '))
    $exitCode = 1
}
exit $exitCode
