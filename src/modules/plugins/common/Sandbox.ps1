# Sandbox.ps1 -- Redirect plugin paths away from the real system.
#
# Testing symlink creation against the live Program Files is how you discover
# that a path was wrong only after it has already been written. The sandbox maps
# every system root onto a scratch tree so the same code path can be exercised
# without touching the machine.
#
#   sources:  S:\Plugins      ->  S:\Plugins\Test
#   targets:  C:\Program Files ->  C:\Test\ProgramFiles   (and so on)
#
# Registry and process steps are suppressed entirely while the sandbox is on:
# there is no meaningful "sandboxed registry", and running a vendor kill script
# would affect the live install. See Invoke-Reconcile's callers for that gate.
#
# Matching is anchored at the start of the path and must end on a directory
# boundary, so C:\Program Files matches C:\Program Files\X but never
# C:\Program Files (x86)\X.

$PluginSandbox = $null

# Get-SandboxPathMap -- Build the prefix -> replacement table.
function Get-SandboxPathMap {
    param(
        [Parameter(Mandatory)] [string]$TargetRoot,
        [string]$SourceFrom = '',
        [string]$SourceTo   = ''
    )

    $map = [ordered]@{}

    # Order is irrelevant here because matching requires a directory boundary,
    # which keeps C:\Program Files and C:\Program Files (x86) independent.
    $pairs = @(
        @{ Env = 'CommonProgramFiles'; Sub = 'CommonProgramFiles' }
        @{ Env = 'ProgramFiles';       Sub = 'ProgramFiles' }
        @{ Env = 'ProgramFiles(x86)';  Sub = 'ProgramFilesX86' }
        @{ Env = 'ProgramData';        Sub = 'ProgramData' }
        @{ Env = 'AppData';            Sub = 'AppData\Roaming' }
        @{ Env = 'LocalAppData';       Sub = 'AppData\Local' }
        @{ Env = 'Public';             Sub = 'Users\Public' }
        @{ Env = 'UserProfile';        Sub = 'Users' }
    )

    foreach ($p in $pairs) {
        $value = [Environment]::GetEnvironmentVariable($p.Env)
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        $map[$value.TrimEnd('\')] = (Join-Path $TargetRoot $p.Sub).TrimEnd('\')
    }

    if ($SourceFrom -and $SourceTo) {
        $map[$SourceFrom.TrimEnd('\')] = $SourceTo.TrimEnd('\')
    }

    $map
}

# Enable-Sandbox -- Turn path redirection on for the current session.
function Enable-Sandbox {
    param(
        [string]$SourceRoot = 'S:\Plugins\Test',
        [string]$TargetRoot = 'C:\Test',
        [string]$RealSourceRoot = ''
    )

    $map = Get-SandboxPathMap -TargetRoot $TargetRoot -SourceFrom $RealSourceRoot -SourceTo $SourceRoot

    # Only the target root is checked. The source root is *meant* to sit inside
    # the real plugin root (S:\Plugins\Test inside S:\Plugins) -- that is what
    # the source mapping expresses, and ConvertTo-SandboxPath recognises the
    # already-rewritten form and leaves it alone.
    #
    # A target root nested inside a mapped root is a different matter: the first
    # rewrite relocates it under the scratch tree, and the relocated path still
    # matches the original key, so a second pass doubles the prefix.
    foreach ($key in $map.Keys) {
        if ($TargetRoot -match ('^' + [regex]::Escape($key) + '(?=\\|$)')) {
            throw ("Sandbox target root '{0}' is inside the mapped root '{1}'. " +
                   "Pick a location outside it, otherwise redirection is not idempotent.") -f $TargetRoot, $key
        }
    }

    $script:PluginSandbox = [PSCustomObject]@{
        Enabled      = $true
        SourceRoot   = $SourceRoot
        TargetRoot   = $TargetRoot
        Map          = $map
    }

    foreach ($dir in @($SourceRoot, $TargetRoot)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    $script:PluginSandbox
}

# Disable-Sandbox -- Turn path redirection back off.
function Disable-Sandbox {
# Held in script scope: the dot-sourced file and its caller share it, and an
# unqualified assignment inside Enable-Sandbox would otherwise create a
# function-local variable that vanishes on return.
$script:PluginSandbox = $null
}

# Test-SandboxActive -- True when path redirection is on.
function Test-SandboxActive {
    return ($null -ne $script:PluginSandbox -and $script:PluginSandbox.Enabled)
}

# ConvertTo-SandboxPath -- Rewrite a real path into its sandboxed equivalent.
#
# Idempotency is handled explicitly rather than by regex alone. A path already
# inside the sandbox still matches the S:\Plugins prefix (S:\Plugins\Test\X
# matches ^S:\Plugins followed by a separator), so without the early return it
# would be rewritten a second time into S:\Plugins\Test\Test\X.
#
# Unmapped paths pass through, which surfaces unexpected roots as real paths
# rather than silently relocating them.
function ConvertTo-SandboxPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    if (-not (Test-SandboxActive)) { return $Path }

    foreach ($from in $script:PluginSandbox.Map.Keys) {
        $pattern = '^' + [regex]::Escape($from) + '(?=\\|$)'
        if ($Path -notmatch $pattern) { continue }

        $replacement = $script:PluginSandbox.Map[$from]
        $remainder   = $Path.Substring($from.Length)

        # Already inside the target side of this mapping: leave it alone.
        if ($replacement -and ($remainder -eq '' -or $Path.StartsWith($replacement + '\', [System.StringComparison]::OrdinalIgnoreCase))) {
            return $Path
        }

        return $replacement + $remainder
    }

    $Path
}

# Get-SandboxPluginRoot -- The plugin folder to read from while sandboxed.
function Get-SandboxPluginRoot {
    param([string]$RealPluginRoot)
    if (Test-SandboxActive) { return $script:PluginSandbox.SourceRoot }
    $RealPluginRoot
}

# Get-SandboxScanRoots -- Target roots for adopt to scan while sandboxed.
#
# Mirrors the root list used by scripts/generate-manifests.ps1 and
# scripts/audit-plugins.ps1. An earlier version listed only the four plugin
# directories, which made sandboxed adopt miss anything under ProgramData,
# AppData or Public -- Waves alone puts links in five of those -- so a later
# revert could only undo part of what apply had done.
function Get-SandboxScanRoots {
    if (-not (Test-SandboxActive)) { return $null }

    $t = $script:PluginSandbox.TargetRoot
    @(
        'VSTPlugins'
        'CommonProgramFiles\VST3'
        'CommonProgramFiles\Avid\Audio\Plug-Ins'
        'ProgramFiles\Steinberg\VSTPlugins'
        'CommonProgramFiles'
        'ProgramFilesX86'
        'ProgramData'
        'AppData'
        'Users\Public'
        'Users\Documents'
    ) | ForEach-Object { Join-Path $t $_ }
}

# Format-SandboxBanner -- One-line reminder printed at the start of a run.
function Format-SandboxBanner {
    if (-not (Test-SandboxActive)) { return }

    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor Yellow
    Write-Host "   SANDBOX: sources and targets are redirected. Nothing" -ForegroundColor Yellow
    Write-Host ("   real is touched. sources : {0}" -f $script:PluginSandbox.SourceRoot) -ForegroundColor Yellow
    Write-Host ("              targets : {0}" -f $script:PluginSandbox.TargetRoot) -ForegroundColor Yellow
    Write-Host "   registry and process steps are skipped." -ForegroundColor Yellow
    Write-Host "  ============================================================" -ForegroundColor Yellow
}