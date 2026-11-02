# host-paths.ps1 -- the per-host path declaration.
#
# Absolute paths rot. S:\Git, C:\Tools and S:\Plugins were hardcoded in three
# different places; on a host whose layout differs they pointed at nothing, and
# nothing said so. The paths are DECLARED per host now, in one file:
#
#   <data dir>\hosts\<COMPUTERNAME>.json
#
# The data dir is the synced store (%USERPROFILE%\Storage\winos\data) when it
# exists and the repository's own data\ directory otherwise. That rule used to
# be a silent `if` in src/vars.ps1 (task T24 in .agent/tasks/manifest.md); the
# ORDER has not changed, the choice is now returned and printed.
#
# This file is the ONLY place that knows the built-in defaults and the ONLY
# place that reports a missing declaration. Everything else asks for the
# resolved values, so a host that has not been declared yet still works -- but
# says so out loud instead of silently using someone else's layout.
#
# Nothing here touches the network, the registry or the file system beyond
# reading one small JSON file.

# Get-WinosPathSeparator -- the separator this platform uses in a path.
#
# Windows paths are joined with a backslash; everywhere else with a slash.
# The tool runs on Windows, but it is also exercised on other hosts (CI, a
# container), and Join-Path there refuses a Windows-style base outright
# ("cannot find drive") -- so the joining is done here instead.
function Get-WinosPathSeparator {
    if ($env:OS -eq 'Windows_NT') { return '\' }
    return '/'
}

# Join-WinosPath -- join a base and a child path without touching the disk.
function Join-WinosPath {
    param([string]$Base, [string]$Child)

    if (-not $Base) { return $Child }
    return ($Base.TrimEnd('\', '/') + (Get-WinosPathSeparator) + $Child)
}

# Get-WinosUserProfile -- the user's profile directory.
#
# %USERPROFILE% on Windows. On a non-Windows host (CI, a container) the
# variable does not exist and %HOME% is the closest equivalent -- without the
# fallback every Join-Path below would fail with "cannot bind argument to
# parameter Path because it is null", which is exactly the class of failure
# this file exists to prevent.
function Get-WinosUserProfile {
    if ($env:USERPROFILE) { return $env:USERPROFILE }
    if ($env:HOME)         { return $env:HOME }
    return 'C:\Users\winos'
}

# Get-WinosHostName -- the name a declaration is looked up under.
#
# COMPUTERNAME on Windows. HOSTNAME elsewhere, so the same lookup works when
# the tool is exercised off Windows. "unknown-host" is the last resort: it
# makes the lookup fail loudly instead of quietly reading a declaration that
# belongs to a different machine.
function Get-WinosHostName {
    if ($env:COMPUTERNAME) { return $env:COMPUTERNAME }
    if ($env:HOSTNAME)     { return $env:HOSTNAME }
    return 'unknown-host'
}

# Get-WinosDataDir -- where the machine state lives, and which rule chose it.
#
# Two candidates, in this order:
#   1. %USERPROFILE%\Storage\winos\data -- the synced store. It survives a
#      reinstall of the checkout and holds the machine-local state.
#   2. <repo>\data -- the repository's own data directory.
#
# THE PRECEDENCE IS UNCHANGED. What changed is that the choice is returned
# instead of being swallowed, and printed, so a machine whose winos reads its
# config from the store says so instead of looking broken.
function Get-WinosDataDir {
    param([string]$RepoRoot)

    $machineDir = Join-WinosPath (Join-WinosPath (Join-WinosPath (Get-WinosUserProfile) 'Storage') 'winos') 'data'
    if (Test-Path -LiteralPath $machineDir) {
        return [PSCustomObject]@{ Path = $machineDir; Source = 'machine store' }
    }
    if ($RepoRoot) {
        return [PSCustomObject]@{ Path = (Join-WinosPath $RepoRoot 'data'); Source = 'repository' }
    }
    return [PSCustomObject]@{ Path = $machineDir; Source = 'machine store (default)' }
}

# Get-WinosDefaultHostPaths -- the built-in defaults, used when a host has no
# declaration. These are the values that used to be hardcoded at their use
# sites; they live here so there is one list to change.
#
# pluginRoot keeps the old fallback chain: S:\Plugins when the library is
# there, otherwise %USERPROFILE%\Plugins when that is there, otherwise the
# convention itself (the probe reports it as missing).
function Get-WinosDefaultHostPaths {
    $pluginDefault = 'S:\Plugins'
    if (-not (Test-Path -LiteralPath 'S:\Plugins')) {
        $userPlugins = Join-WinosPath (Get-WinosUserProfile) 'Plugins'
        if (Test-Path -LiteralPath $userPlugins) { $pluginDefault = $userPlugins }
    }

    return [ordered]@{
        projectsDir          = 'S:\Git'
        toolsDir             = 'C:\Tools'
        pluginRoot           = $pluginDefault
        taskWorkingDirectory = 'S:\Git'
    }
}

# Expand-WinosPathValue -- expand the tokens a declared path may carry.
#
# %VAR% and $env:VAR are expanded, and %USERPROFILE% is expanded even on a
# non-Windows host (where ExpandString does not know the name). A path with
# no token comes back unchanged.
function Expand-WinosPathValue {
    param([string]$Value)

    if (-not $Value) { return $Value }
    $expanded = $ExecutionContext.InvokeCommand.ExpandString($Value)
    $expanded = $expanded.Replace('%USERPROFILE%', (Get-WinosUserProfile))
    return $expanded
}

# Resolve-WinosHostPaths -- read the declaration of this host and return the
# resolved paths.
#
# Returns a PSCustomObject with:
#   hostName             -- the name the lookup was made under
#   declarationFile      -- the file that was looked for
#   declarationFound     -- whether it was there and could be parsed
#   declarationSource    -- 'declaration (<file>)' or 'built-in defaults'
#   dataDir / dataSource -- where the machine state lives and why
#   projectsDir          -- the checkout root of this host
#   toolsDir             -- where the tools live on this host
#   pluginRoot           -- the plugin library (read-only)
#   taskWorkingDirectory -- the working directory a scheduled task starts in
#   tasks                -- optional per-task overrides from the declaration
#
# -State is a hashtable the CALLER owns. It is how "warn once" is kept
# without a global: the caller passes the same hashtable to every resolution
# and the warning is emitted only the first time.
#
# -Quiet suppresses the reporting. The report is not decoration: a host
# without a declaration runs on the built-in defaults, and that has to be
# visible, otherwise the next broken absolute path is discovered the hard way.
function Resolve-WinosHostPaths {
    [CmdletBinding()]
    param(
        [string]$DataDir,
        [string]$RepoRoot,
        [hashtable]$State,
        [switch]$Quiet
    )

    $hostName = Get-WinosHostName

    $dataInfo = if ($DataDir) {
        [PSCustomObject]@{ Path = $DataDir; Source = 'explicit' }
    } else {
        Get-WinosDataDir -RepoRoot $RepoRoot
    }

    $declarationFile = Join-WinosPath (Join-WinosPath $dataInfo.Path 'hosts') "$hostName.json"
    $declaration = $null
    $found = $false
    if (Test-Path -LiteralPath $declarationFile) {
        try {
            $declaration = Get-Content -Raw -LiteralPath $declarationFile | ConvertFrom-Json -ErrorAction Stop
            $found = $true
        } catch {
            Write-Warning "Host declaration '$declarationFile' is unreadable: $($_.Exception.Message)"
        }
    }

    $defaults = Get-WinosDefaultHostPaths
    $values = @{}
    foreach ($key in $defaults.Keys) { $values[$key] = $defaults[$key] }
    $source = 'built-in defaults'

    if ($found -and $declaration) {
        foreach ($key in $defaults.Keys) {
            $prop = $declaration.PSObject.Properties[$key]
            if ($prop -and $prop.Value) { $values[$key] = [string]$prop.Value }
        }
        # taskWorkingDirectory follows projectsDir when the declaration names
        # only the latter: a task usually starts in the checkout root.
        $hasWorkingDir = $declaration.PSObject.Properties['taskWorkingDirectory'] -and
                         $declaration.taskWorkingDirectory
        if (-not $hasWorkingDir) { $values['taskWorkingDirectory'] = $values['projectsDir'] }
        $source = "declaration ($declarationFile)"
    }

    foreach ($key in @($values.Keys)) {
        $values[$key] = Expand-WinosPathValue -Value $values[$key]
    }

    # Optional per-task overrides. A scheduled task may need a script that
    # lives outside the checkout root; the declaration is where that path
    # belongs, not in the code.
    $taskOverrides = $null
    if ($found -and $declaration) {
        $prop = $declaration.PSObject.Properties['tasks']
        if ($prop -and $prop.Value) { $taskOverrides = $prop.Value }
    }

    if (-not $Quiet) {
        if ($found) {
            Write-Host ("winos: data dir = {0} ({1}); host declaration = {2} (read)" -f `
                $dataInfo.Path, $dataInfo.Source, $declarationFile) -ForegroundColor DarkGray
        } else {
            # The warning is emitted ONCE per state. The caller owns the state
            # (src/vars.ps1 keeps one for the whole run), so a second
            # resolution in the same session does not repeat the warning --
            # while the summary line below still prints every time.
            $alreadyWarned = ($null -ne $State) -and
                             $State.ContainsKey('MissingDeclarationWarned') -and
                             $State['MissingDeclarationWarned']
            if (-not $alreadyWarned) {
                if ($null -ne $State) { $State['MissingDeclarationWarned'] = $true }
                $listed = @(
                    "projectsDir=$($defaults['projectsDir'])"
                    "toolsDir=$($defaults['toolsDir'])"
                    "pluginRoot=$($defaults['pluginRoot'])"
                )
                Write-Warning (("No host declaration for '{0}': {1} not found - falling back to " +
                    "the built-in defaults ({2}).") -f $hostName, $declarationFile, ($listed -join ', '))
            }
            Write-Host ("winos: data dir = {0} ({1}); host declaration = {2} (missing - defaults used)" -f `
                $dataInfo.Path, $dataInfo.Source, $declarationFile) -ForegroundColor DarkGray
        }
    }

    return [PSCustomObject]@{
        hostName             = $hostName
        declarationFile      = $declarationFile
        declarationFound     = $found
        declarationSource    = $source
        dataDir              = $dataInfo.Path
        dataSource           = $dataInfo.Source
        projectsDir          = $values['projectsDir']
        toolsDir             = $values['toolsDir']
        pluginRoot           = $values['pluginRoot']
        taskWorkingDirectory = $values['taskWorkingDirectory']
        tasks                = $taskOverrides
    }
}
