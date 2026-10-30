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
      * an already installed opencode is never downgraded silently
      * the running opencode server is never stopped or restarted

    Exit codes: 0 = ok, 1 = a required item is missing or mismatched.

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
    [string]$OpenCodeVersion = '2.2.1',
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
    PluginVersion         = 'oh-my-opencode-slim@3.0.5'
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
$ServeSh   = Join-Path $env:USERPROFILE 'opencode-serve.sh'
$ComputerUseDir = 'C:\Tools\opencode-computer-use'

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

function Invoke-Native {
    param([string]$Exe, [string[]]$Arguments)
    $out = & $Exe @Arguments 2>&1
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = ($out | Out-String)
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

function Test-ScoopBucket {
    param([string]$Name)
    $res = Invoke-Native 'scoop' @('bucket', 'list')
    return ($res.Output -match "(?m)^\s*$([regex]::Escape($Name))\s")
}

function Get-NpmGlobalPackage {
    param([string]$Name)
    $res = Invoke-Native 'npm' @('ls', '-g', '--depth=0', '--json')
    if ($res.ExitCode -ne 0) { return $null }
    try { $json = $res.Output | ConvertFrom-Json } catch { return $null }
    if ($json.dependencies -and ($json.dependencies.PSObject.Properties.Name -contains $Name)) {
        return $json.dependencies.$Name.version
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

# --------------------------------------------------------------------------
# Config templates (ASCII; path placeholders are substituted at write time)
# --------------------------------------------------------------------------
$OpenCodeJsonTemplate = @'
{
  "model": "opencode-go/deepseek-v4.1-flash",
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "servers": {
      "webpage": {
        "type": "local",
        "command": [
          "cmd",
          "/c",
          "__USERPROFILE__\\scoop\\apps\\nodejs\\current\\npx.cmd",
          "-y",
          "-p",
          "webpage-mcp@latest",
          "webpage-mcp-stdio"
        ]
      },
      "browser-control": {
        "type": "local",
        "command": [
          "cmd",
          "/c",
          "__USERPROFILE__\\scoop\\apps\\nodejs\\current\\bin\\browser-control-mcp.cmd"
        ]
      },
      "computer-use": {
        "type": "local",
        "command": ["__TOOLS__\\opencode-computer-use\\.venv\\Scripts\\python.exe", "-m", "opencode_computer_use"],
        "cwd": "__TOOLS__\\opencode-computer-use",
        "enabled": true,
        "timeout": 60000,
        "environment": {
          "COMPUTER_USE_LOG_LEVEL": "INFO",
          "COMPUTER_USE_SINGLE_MONITOR": "0",
          "COMPUTER_USE_MONITOR": "0",
          "COMPUTER_USE_AUTONOMOUS": "0",
          "COMPUTER_USE_MAX_WIDTH": "1920",
          "COMPUTER_USE_OVERLAY_AUTO": "1",
          "COMPUTER_USE_OVERLAY_IDLE_SEC": "10"
        }
      },
      "genoffice": {
        "type": "local",
        "command": ["cmd", "/c", "__LOCALAPPDATA__\\Programs\\GenOffice\\resources\\cli\\genoffice.cmd", "mcp"],
        "enabled": true,
        "timeout": 120000
      }
    }
  },
  "plugins": ["oh-my-opencode-slim@3.0.5"]
}
'@

# tui.json keeps its own plugin entry on purpose: the registry names the
# divergence between tui.json and opencode.jsonc / cli.json and does not
# "fix" it. Reproduce the machine as it is.
$TuiJsonTemplate = @'
{
  "plugin": [
    "oh-my-openagent@latest"
  ]
}
'@

$CliJsonTemplate = @'
{
  "$schema": "https://opencode.ai/v2/cli.json",
  "plugins": ["oh-my-opencode-slim@3.0.5"]
}
'@

$OhMyOpenCodeSlimTemplate = @'
{
  "agents": {
    "orchestrator": {
      "model": "opencode-go/deepseek-v4.1-flash"
    },
    "explorer": {
      "model": "opencode-go/deepseek-v4.1-flash"
    },
    "oracle": {
      "model": "opencode-go/deepseek-v4.1-flash"
    },
    "designer": {
      "model": "opencode-go/deepseek-v4.1-flash"
    },
    "fixer": {
      "model": "opencode-go/deepseek-v4.1-flash"
    }
  }
}
'@

function Expand-Template {
    param([string]$Template)
    $t = $Template.Replace('__USERPROFILE__', $env:USERPROFILE)
    $t = $t.Replace('__LOCALAPPDATA__', $env:LOCALAPPDATA)
    $t = $t.Replace('__TOOLS__', 'C:\Tools')
    return $t
}

# --------------------------------------------------------------------------
# Check framework
#
# Every check scriptblock takes one argument: a hashtable of context values.
# The context is stored next to the scriptblock and passed in at call time.
# This avoids PowerShell's late-binding closure behaviour: a scriptblock that
# reads a loop variable directly would see the LAST loop value, not its own.
# --------------------------------------------------------------------------
$Checks = New-Object System.Collections.ArrayList

function Add-Check {
    param(
        [string]$Name,
        [string]$Detail,
        [hashtable]$Context,
        [scriptblock]$Test,     # returns $true when the item is already satisfied
        [scriptblock]$Install,  # performs the install; $true on success
        [bool]$Required = $true
    )
    [void]$Checks.Add([pscustomobject]@{
        Name = $Name; Detail = $Detail; Context = $Context
        Test = $Test; Install = $Install; Required = $Required
    })
}

# --- 1. scoop ------------------------------------------------------------
Add-Check -Name 'scoop' -Detail "scoop $($Registry.ScoopVersion) in $ScoopRoot" -Context @{} -Required $true -Test {
    param($d)
    (Get-Command scoop -ErrorAction SilentlyContinue) -ne $null
} -Install {
    param($d)
    Write-Note 'installing scoop from https://get.scoop.sh'
    $r = Invoke-Native 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command',
        "Invoke-WebRequest https://get.scoop.sh -UseBasicParsing | Invoke-Expression")
    if ($r.ExitCode -ne 0) { Write-Fail "scoop installer failed: $($r.Output.Trim())"; return $false }
    Ensure-ScoopOnPath
    return ((Get-Command scoop -ErrorAction SilentlyContinue) -ne $null)
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
        $r = Invoke-Native 'scoop' @('bucket', 'add', $d.Bucket, $d.Url)
        if ($r.ExitCode -ne 0 -and -not (Test-ScoopBucket -Name $d.Bucket)) {
            Write-Fail "scoop bucket add $($d.Bucket) failed: $($r.Output.Trim())"; return $false
        }
        return $true
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
        (Get-ScoopAppVersion -App $d.App) -ne $null
    } -Install {
        param($d)
        $r = Invoke-Native 'scoop' @('install', "$($d.Bucket)/$($d.App)")
        if ($r.ExitCode -ne 0 -and (Get-ScoopAppVersion -App $d.App) -eq $null) {
            Write-Fail "scoop install $($d.Bucket)/$($d.App) failed: $($r.Output.Trim())"; return $false
        }
        return $true
    }
}

# --- 4. opencode ---------------------------------------------------------
Add-Check -Name 'app:opencode2' -Detail "opencode2 $($Registry.OpenCodeVersion) (bucket versions)" `
    -Context @{ Want = $Registry.OpenCodeVersion; Latest = [bool]$AllowLatestOpenCode } -Required $true -Test {
    param($d)
    (Get-ScoopAppVersion -App 'opencode2') -ne $null
} -Install {
    param($d)
    if ($d.Latest) {
        $r = Invoke-Native 'scoop' @('install', 'versions/opencode2')
        if ($r.ExitCode -ne 0 -and (Get-ScoopAppVersion -App 'opencode2') -eq $null) {
            Write-Fail "scoop install versions/opencode2 failed: $($r.Output.Trim())"; return $false
        }
        return $true
    }
    # Pin the exact version through the bucket manifest that shipped it.
    $sha = Invoke-Native 'git' @('log', '--format=%H', '-n', '30', '--', 'bucket/opencode2.json')
    $commit = ''
    foreach ($line in ($sha.Output -split "`n")) {
        $c = $line.Trim()
        if (-not $c) { continue }
        $probe = Invoke-Native 'git' @('show', "${c}:bucket/opencode2.json")
        if ($probe.ExitCode -eq 0 -and
            $probe.Output -match ('"version"\s*:\s*"' + [regex]::Escape($d.Want) + '"')) {
            $commit = $c; break
        }
    }
    if (-not $commit) {
        Write-Warn2 "no manifest for opencode2 $($d.Want) in the versions bucket history; installing the latest instead"
        $r = Invoke-Native 'scoop' @('install', 'versions/opencode2')
        return ($r.ExitCode -eq 0) -or ((Get-ScoopAppVersion -App 'opencode2') -ne $null)
    }
    $short = $commit.Substring(0, [Math]::Min(10, $commit.Length))
    $manifest = "https://raw.githubusercontent.com/ScoopInstaller/Versions/$short/bucket/opencode2.json"
    Write-Note "installing pinned opencode2 $($d.Want) from $manifest"
    $r = Invoke-Native 'scoop' @('install', $manifest)
    if ($r.ExitCode -ne 0 -and (Get-ScoopAppVersion -App 'opencode2') -eq $null) {
        Write-Fail "scoop install <pinned manifest> failed: $($r.Output.Trim())"; return $false
    }
    return $true
}

# --- 5. global npm package ----------------------------------------------
Add-Check -Name 'npm:@opencode-ai/browser-control' `
    -Detail "npm -g @opencode-ai/browser-control@$($Registry.BrowserControlVersion)" `
    -Context @{ Want = $Registry.BrowserControlVersion } -Required $true -Test {
    param($d)
    (Get-NpmGlobalPackage -Name '@opencode-ai/browser-control') -ne $null
} -Install {
    param($d)
    $r = Invoke-Native 'npm' @('install', '-g', "@opencode-ai/browser-control@$($d.Want)")
    if ($r.ExitCode -ne 0 -and (Get-NpmGlobalPackage -Name '@opencode-ai/browser-control') -eq $null) {
        Write-Fail "npm install -g failed: $($r.Output.Trim())"; return $false
    }
    return $true
}

# --- 6. opencode config files --------------------------------------------
$ConfigFiles = @(
    @{ File = 'opencode.jsonc';           Template = $OpenCodeJsonTemplate;      Marker = 'browser-control' },
    @{ File = 'cli.json';                 Template = $CliJsonTemplate;           Marker = 'oh-my-opencode-slim' },
    @{ File = 'tui.json';                 Template = $TuiJsonTemplate;           Marker = 'oh-my-openagent' },
    @{ File = 'oh-my-opencode-slim.json'; Template = $OhMyOpenCodeSlimTemplate; Marker = 'orchestrator' }
)
foreach ($cf in $ConfigFiles) {
    $cfgFile   = $cf.File
    $cfgTpl    = $cf.Template
    $cfgMarker = $cf.Marker
    Add-Check -Name "config:$cfgFile" -Detail "$ConfigDir\$cfgFile" `
        -Context @{ File = $cfgFile; Template = $cfgTpl; Marker = $cfgMarker } -Required $true -Test {
        param($d)
        $p = Join-Path $ConfigDir $d.File
        (Test-Path -LiteralPath $p) -and ((Get-Content -Raw -LiteralPath $p) -match [regex]::Escape($d.Marker))
    } -Install {
        param($d)
        $p = Join-Path $ConfigDir $d.File
        if ((Test-Path -LiteralPath $p) -and -not $Force) {
            Write-Warn2 "$($d.File) exists and is left untouched (use -Force to rewrite it)"
            return $true
        }
        Write-Note "writing $p"
        Write-TextFile -Path $p -Content (Expand-Template -Template $d.Template)
        return $true
    }
}

# --- 7. computer-use venv -------------------------------------------------
Add-Check -Name 'venv:computer-use' -Detail "$ComputerUseDir\.venv (python -m opencode_computer_use)" `
    -Context @{ Dir = $ComputerUseDir } -Required $true -Test {
    param($d)
    $py = Join-Path $d.Dir '.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $py)) { return $false }
    $r = Invoke-Native $py @('-c', 'import opencode_computer_use')
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
    $r = Invoke-Native $py @('-c', 'import opencode_computer_use')
    return ($r.ExitCode -eq 0)
}

# --- 8. egress proxy (report only, never setx) ---------------------------
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
    Write-Warn2 '  the provider opencode-go is then absent from the registry and'
    Write-Warn2 "  the default model $($Registry.DefaultModel) is unavailable."
    Write-Warn2 'Set these BEFORE starting the server (this script never runs setx):'
    Write-Warn2 "  export HTTP_PROXY=$($d.Url)"
    Write-Warn2 "  export HTTPS_PROXY=$($d.Url)"
    Write-Warn2 "  export NO_PROXY=$($d.NoProxy)"
    Write-Warn2 '  for a Windows session: setx HTTP_PROXY "URL" / setx NO_PROXY "LIST"'
    return $false
}

# --- 9. auth (report only) ------------------------------------------------
Add-Check -Name 'auth:login' `
    -Detail 'opencode auth list - logins are redone, auth.json is NOT migrated' `
    -Context @{ DataDir = $DataDir } -Required $false -Test {
    param($d)
    $p = Join-Path $d.DataDir 'auth.json'
    if (-not (Test-Path -LiteralPath $p)) { return $false }
    $r = Invoke-Native 'opencode' @('auth', 'list')
    return ($r.ExitCode -eq 0)
} -Install {
    param($d)
    Write-Warn2 'no usable auth.json / opencode auth list failed.'
    Write-Warn2 'auth.json is not migrated by design - run:  opencode auth login'
    Write-Warn2 'The OpenCode Console account lives in opencode.db (table credential),'
    Write-Warn2 'so either carry opencode.db over or log in again.'
    return $false
}

# --- 10. serve launcher (report only) -------------------------------------
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
}

# --------------------------------------------------------------------------
# Run
# --------------------------------------------------------------------------
Ensure-ScoopOnPath
$exitCode = 0
$failures = New-Object System.Collections.ArrayList

function Test-Check {
    param($c)
    try { return [bool](& $c.Test $c.Context) } catch { return $false }
}

if ($Verify) {
    Write-Head 'VERIFY (read only)'
    foreach ($c in $Checks) {
        if (Test-Check $c) {
            Write-Ok ("{0} - {1}" -f $c.Name, $c.Detail)
        } else {
            if ($c.Required) {
                Write-Fail ("{0} - {1}" -f $c.Name, $c.Detail)
                [void]$failures.Add($c.Name)
            } else {
                Write-Warn2 ("{0} - {1}" -f $c.Name, $c.Detail)
            }
        }
    }

    # Advisory checks that need the network: informational only.
    Write-Head 'ADVISORY'
    $models = Invoke-Native 'opencode' @('models')
    if ($models.ExitCode -ne 0) {
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

    Write-Head 'RESULT'
    if ($failures.Count -eq 0) {
        Write-Ok 'all required items match the registry'
    } else {
        Write-Fail ("missing or mismatched: " + ($failures -join ', '))
        $exitCode = 1
    }
    exit $exitCode
}

if ($DryRun) {
    Write-Head 'DRY RUN (nothing is changed)'
    foreach ($c in $Checks) {
        if (Test-Check $c) {
            Write-Ok ("already done: {0} - {1}" -f $c.Name, $c.Detail)
        } else {
            Write-Plan ("would do: {0} - {1}" -f $c.Name, $c.Detail)
        }
    }
    Write-Head 'RESULT'
    Write-Note 'dry run finished, nothing was changed'
    exit 0
}

Write-Head 'INSTALL'
foreach ($c in $Checks) {
    if (Test-Check $c) {
        Write-Ok ("already done: {0}" -f $c.Name)
        continue
    }
    Write-Note ("installing: {0} - {1}" -f $c.Name, $c.Detail)
    $done = $false
    try { $done = [bool](& $c.Install $c.Context) } catch {
        Write-Fail ("{0} threw: {1}" -f $c.Name, $_.Exception.Message)
        $done = $false
    }
    if ($done) {
        Write-Ok ("done: {0}" -f $c.Name)
    } elseif ($c.Required) {
        Write-Fail ("FAILED: {0}" -f $c.Name)
        [void]$failures.Add($c.Name)
    } else {
        Write-Warn2 ("not done (advisory): {0}" -f $c.Name)
    }
}

Write-Head 'RESULT'
if ($failures.Count -eq 0) {
    Write-Ok 'installation finished without failures'
    Write-Note 'remaining manual steps:'
    Write-Note '  1. export HTTP_PROXY / HTTPS_PROXY / NO_PROXY for the server environment'
    Write-Note '  2. opencode auth login   (auth.json is not migrated)'
    Write-Note '  3. decide the default model (docs/opencode-registry.md section 0.3)'
} else {
    Write-Fail ("failed items: " + ($failures -join ', '))
    $exitCode = 1
}
exit $exitCode
