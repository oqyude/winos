[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("plan", "apply", "revert", "snapshot", "status", "adopt", "verify")]
    [string]$action,
    [switch]$Force,
    [switch]$Sandbox,
    [string]$SandboxSource,
    [string]$SandboxTarget
)

# Self-bootstrap: source init.ps1 if vars aren't set (allows standalone -File invocation).
# Placed after param() because [CmdletBinding()] must precede any executable code.
#
# NOTE: this module sits one level deeper than the symlink-manager. It stayed in
# src/modules/plugins/ after the two engines were merged -- see the note at the
# State.ps1 dot-source below. Hence '..\..' to reach src/init.ps1.
if (-not $root) {
    . (Join-Path $PSScriptRoot "..\..\init.ps1")
}

# Paths this module needs. src/vars.ps1 (sourced by init.ps1) defines the winos
# module registry and its own variables, but knows nothing about plugin paths, so
# they are declared here rather than added to a file the other modules share.
. (Join-Path $PSScriptRoot "vars.ps1")

# Source common helpers
# State.ps1 is shared with the symlink-manager and lives one level up, at
# src\modules\common\. It used to sit beside this file as plugins\common\State.ps1 --
# two copies defining eight identical function names, loaded by dot-source, where
# whichever loaded last silently won and broke the other module. One engine now.
# The rest of common\ (StateFile, Sandbox, Discovery, Manifest, Verify) are specific
# to plugin deployment and stay local: their names collide with nothing.
. (Join-Path $PSScriptRoot "..\common\State.ps1")
. (Join-Path $PSScriptRoot "common\StateFile.ps1")
. (Join-Path $PSScriptRoot "common\Sandbox.ps1")
. (Join-Path $PSScriptRoot "common\Discovery.ps1")
. (Join-Path $PSScriptRoot "common\Manifest.ps1")
. (Join-Path $PSScriptRoot "common\Verify.ps1")
. (Join-Path $PSScriptRoot "methods\registry-import.ps1")
. (Join-Path $PSScriptRoot "methods\copy-tree.ps1")
. (Join-Path $PSScriptRoot "methods\process-kill.ps1")

# Sandbox must be enabled before any path resolution happens, and $pluginRoot has
# to be re-pointed at the scratch copy so manifest From paths read from there.
$realPluginRoot = $pluginRoot
if ($Sandbox) {
    $sandboxParams = @{}
    if ($SandboxSource) { $sandboxParams['SourceRoot'] = $SandboxSource }
    if ($SandboxTarget) { $sandboxParams['TargetRoot'] = $SandboxTarget }
    Enable-Sandbox @sandboxParams -RealSourceRoot $realPluginRoot | Out-Null
    $pluginRoot = Get-SandboxPluginRoot -RealPluginRoot $realPluginRoot
    # Manifests are shared with real runs; keep looking them up where they live.
    $manifestDir = Join-Path $root 'manifests'
}

if (-not $action) {
    Write-Output "plugin-manager.ps1: no action specified."
    Write-Output "Actions: plan, apply, revert, snapshot, status, adopt, verify"
    Write-Output "Add -Sandbox to redirect sources and targets away from the live system."
    exit 1
}

# --- helpers -----------------------------------------------------------------

# Build-Delta -- Probe current state, categorize into actions.
# Returns the same delta used by plan, apply, revert, and snapshot.
function Build-Delta {
    param(
        [Parameter(Mandatory)] $EntryList
    )
    $delta = @()
    if ($null -eq $EntryList) { return ,$delta }
    foreach ($entry in $EntryList) {
        $entryState = Get-SymlinkEntryState -Entry $entry
        $desired = if ($entry.link) { 'symlink' } else { 'missing' }
        $categorized = Compare-State -EntryState $entryState -Desired $desired
        $delta += $categorized
    }
    , $delta
}

# Invoke-Reconcile -- Apply a delta: create/drop junctions, print per-action
# lines and a summary. Saves snapshot as a side effect.
function Invoke-Reconcile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] $Delta,
        [switch]$Force
    )
    $results = @()
    foreach ($entry in $Delta) {
        if ($entry.method -ne 'symlink') { continue }
        $entryResults = Invoke-SafeAction -EntryState $entry -Force:$Force
        foreach ($r in $entryResults) {
            $icon = switch ($r.action) {
                'noop'     { '~' }
                'create'   { '+' }
                'replace'  { '*' }
                'drop'     { '-' }
                'conflict' { '!' }
            }
            $color = switch ($r.action) {
                'noop'     { 'DarkGray' }
                'create'   { 'Green' }
                'replace'  { 'Yellow' }
                'drop'     { 'DarkCyan' }
                'conflict' { 'Red' }
            }
            $line = "  {0} {1,-10} {2}" -f $icon, $r.status, $r.to
            if ($r.note) { $line += "  ($($r.note))" }
            Write-Host $line -ForegroundColor $color
        }
        $results += $entryResults
    }

    $created  = ($results | Where-Object { $_.status -eq 'created'  }).Count
    $replaced = ($results | Where-Object { $_.status -eq 'replaced' }).Count
    $resolved = ($results | Where-Object { $_.status -eq 'resolved' }).Count
    $removed  = ($results | Where-Object { $_.status -eq 'removed'  }).Count
    $skipped  = ($results | Where-Object { $_.status -eq 'skipped'  }).Count
    $failed   = ($results | Where-Object { $_.status -eq 'failed'   }).Count

    Write-Host ""
    Write-Host ("Created: {0}  Replaced: {1}  Resolved: {2}  Removed: {3}  Skipped: {4}  Failed: {5}" -f $created, $replaced, $resolved, $removed, $skipped, $failed) -ForegroundColor Cyan

    Save-Snapshot -Path $snapshotFile -Delta $Delta | Out-Null
    Write-Host ("Saved: {0}" -f $snapshotFile) -ForegroundColor DarkGray
}

# Print-StepResult -- Format and color-print a method's result object.
function Print-StepResult {
    param($Action, $Result)
    if ($null -eq $Result) { return }
    $icon = switch ($Result.Status) {
        'imported' { '+' }
        'copied'   { '+' }
        'invoked'  { '+' }
        'removed'  { '-' }
        'skipped'  { '~' }
        'failed'   { '!' }
        default    { '?' }
    }
    $color = switch ($Result.Status) {
        'imported' { 'Green' }
        'copied'   { 'Green' }
        'invoked'  { 'Green' }
        'removed'  { 'DarkCyan' }
        'skipped'  { 'DarkGray' }
        'failed'   { 'Red' }
        default    { 'White' }
    }
    $line = "  {0} {1,-12} {2}" -f $icon, $Action, $Result.Status
    if ($Result.Note) { $line += "  ($($Result.Note))" }
    Write-Host $line -ForegroundColor $color
}

# New-SandboxSkipResult -- Describe a step the sandbox refuses to run.
#
# The note names the file and whether it is actually there. A bare "registry
# writes disabled" tells the operator nothing, and a missing .reg is exactly
# the kind of thing that only surfaces once the sandbox is left behind.
function New-SandboxSkipResult {
    param(
        [Parameter(Mandatory)] [string]$Reason,
        [string[]]$Paths = @()
    )

    $shown = foreach ($p in $Paths) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        '{0} exists={1}' -f $p, (Test-Path -LiteralPath $p)
    }
    $note = $Reason
    if (@($shown).Count -gt 0) { $note = '{0} -- {1}' -f $Reason, ($shown -join '; ') }

    [PSCustomObject]@{ Status = 'skipped'; Note = $note }
}

# Invoke-ManifestEnable -- For one entry with a manifest, run enable steps.
# Enable order: copy, then registry (links were already created by Invoke-Reconcile).
function Invoke-ManifestEnable {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] $Manifest,
        [Parameter(Mandatory)] $Entry
    )

    # Manifest-relative paths resolve against the plugin's own folder.
    $pluginDir = Join-Path $pluginRoot $Entry.name

    $hasWork = $false
    foreach ($c in (Get-ManifestCopySteps -Manifest $Manifest -BaseDir $pluginDir)) {
        $hasWork = $true
        $r = Invoke-CopyTree -From $c.From -To $c.To
        Print-StepResult -Action 'copy' -Result $r
    }

    $regSteps = Get-ManifestRegistrySteps -Manifest $Manifest -Action 'enable' -BaseDir $pluginDir
    if (@($regSteps).Count -gt 0) {
        $hasWork = $true
        # Registry imports would write to the live hive. There is no sandboxed
        # registry to redirect into, so the step is reported and skipped.
        if (Test-SandboxActive) {
            Print-StepResult -Action 'reg-enable' -Result (New-SandboxSkipResult `
                -Reason 'sandbox: registry writes disabled' `
                -Paths @($regSteps | ForEach-Object { $_.RegFile }))
        } else {
            foreach ($s in $regSteps) {
                $r = Import-RegistryFile -Path $s.RegFile
                Print-StepResult -Action 'reg-enable' -Result $r
            }
        }
    }
    return $hasWork
}

# Invoke-ManifestDisable -- For one entry with a manifest, run disable steps.
# Disable order: registry (links were already dropped by Invoke-Reconcile).
function Invoke-ManifestDisable {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] $Manifest,
        [Parameter(Mandatory)] $Entry
    )

    $pluginDir = Join-Path $pluginRoot $Entry.name

    $hasWork = $false
    $regSteps = Get-ManifestRegistrySteps -Manifest $Manifest -Action 'disable' -BaseDir $pluginDir
    if (@($regSteps).Count -gt 0) {
        $hasWork = $true
        if (Test-SandboxActive) {
            Print-StepResult -Action 'reg-disable' -Result (New-SandboxSkipResult `
                -Reason 'sandbox: registry writes disabled' `
                -Paths @($regSteps | ForEach-Object { $_.RegFile }))
        } else {
            foreach ($s in $regSteps) {
                $r = Import-RegistryFile -Path $s.RegFile
                Print-StepResult -Action 'reg-disable' -Result $r
            }
        }
    }
    return $hasWork
}

# Invoke-ManifestProcessSteps -- Run beforeRevert process steps for one manifest.
function Invoke-ManifestProcessSteps {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] $Manifest,
        [Parameter(Mandatory)] $Entry
    )
    $pluginDir = Join-Path $pluginRoot $Entry.name

    $procSteps = Get-ManifestProcessSteps -Manifest $Manifest -Trigger 'beforeRevert' -BaseDir $pluginDir
    if (@($procSteps).Count -eq 0) { return $false }

    # Vendor kill scripts act on the live install. Running them from a sandbox
    # run would terminate real processes, so the step is reported and skipped.
    if (Test-SandboxActive) {
        Print-StepResult -Action 'process' -Result (New-SandboxSkipResult `
            -Reason 'sandbox: process scripts disabled' `
            -Paths @($procSteps | ForEach-Object { $_.Script }))
        return $true
    }

    foreach ($s in $procSteps) {
        $r = Invoke-ProcessScript -ScriptPath $s.Script -WorkDir $pluginDir
        Print-StepResult -Action 'process' -Result $r
    }
    return $true
}

# Resolve-EntryMappings -- Fill in an entry's link mappings.
#
# Precedence, most explicit first:
#   1. state.json `mappings` -- explicit per-link config.
#   2. manifest `Links`       -- the vendor's intended install layout.
#   3. layout heuristics      -- infer from the plugin folder's own structure.
#   4. single from/to         -- handled downstream by Get-SymlinkEntryState.
#
# Step 3 is what makes dropping a folder into S:\Plugins enough on its own;
# without it a plugin with no manifest would silently resolve to zero links.
function Resolve-EntryMappings {
    param([Parameter(Mandatory)] $EntryList)

    $resolved = @()
    foreach ($entry in $EntryList) {
        if ($null -ne $entry.mappings -and @($entry.mappings).Count -gt 0) {
            $resolved += $entry
            continue
        }

        $pluginDir = Join-Path $pluginRoot $entry.name

        $links = @()
        $manifest = Get-PluginManifest -Name $entry.name -ManifestDir $manifestDir
        if ($null -ne $manifest) {
            $links = Get-ManifestLinks -Manifest $manifest -BaseDir $pluginDir
        }

        $links = @($links | ForEach-Object { $_ })

        if ($links.Count -eq 0 -and (Test-Path -LiteralPath $pluginDir -PathType Container)) {
            $links = (Discover-Plugin -PluginDir $pluginDir).Mappings
        }

        if ($links.Count -gt 0) {
            $entry.mappings = $links
        }
        $resolved += $entry
    }
    , $resolved
}

# --- main dispatch -----------------------------------------------------------

Format-SandboxBanner

$state = Read-PowerLinksState -Path $stateFile
$entries = Get-EnabledPlugins -State $state
$entries = Resolve-EntryMappings -EntryList $entries

switch ($action) {
    "verify" {
        # Pre-flight for whatever apply or revert is about to do. Reads only.
        # scripts/audit-plugins.ps1 covers the whole library; this covers exactly
        # the entries state.json selects, resolved the way apply resolves them.
        Write-Host ""
        Write-Host "  Plugin Deployment :: verify" -ForegroundColor Cyan
        Write-Host "  $('-' * 32)"           -ForegroundColor DarkGray

        $report = Get-VerifyReport -Entries $entries -PluginRoot $pluginRoot -ManifestDir $manifestDir

        Write-Host ""
        if ($report.Problems.Count -eq 0) {
            Write-Host ("  OK: {0} entries, {1} referenced paths all present." -f $entries.Count, $report.Checked) -ForegroundColor Green
            exit 0
        }

        Write-Host "  Problems:" -ForegroundColor Red
        $report.Problems | Sort-Object Kind, Plugin | ForEach-Object {
            Write-Host ("    [{0}] {1}" -f $_.Kind, $_.Plugin) -ForegroundColor Red
            Write-Host ("      {0}" -f $_.Detail) -ForegroundColor DarkGray
        }
        Write-Host ""
        Write-Host ("  {0} entries, {1} paths checked, {2} problem(s)" -f $entries.Count, $report.Checked, $report.Problems.Count) -ForegroundColor Red
        exit 1
    }
    "plan" {
        Write-Host ""
        Write-Host "  Plugin Deployment :: plan" -ForegroundColor Cyan
        Write-Host "  $('-' * 32)"          -ForegroundColor DarkGray
        $delta = Build-Delta -EntryList $entries
        Format-Plan -Delta $delta | Out-Null
        Save-Snapshot -Path $snapshotFile -Delta $delta | Out-Null
        Write-Host ""
        Write-Host ("Saved: {0}" -f $snapshotFile) -ForegroundColor DarkGray
    }
    "apply" {
        Write-Host ""
        Write-Host "  Plugin Deployment :: apply" -ForegroundColor Cyan
        Write-Host "  $('-' * 32)"          -ForegroundColor DarkGray
        $delta = Build-Delta -EntryList $entries
        Invoke-Reconcile -Delta $delta -Force:$Force

        # Manifest steps: run after links for enable, or alongside drops for disable.
        foreach ($entry in $entries) {
            $manifest = Get-PluginManifest -Name $entry.name -ManifestDir $manifestDir
            if ($null -eq $manifest) { continue }
            if ($entry.link) {
                if (Invoke-ManifestEnable -Manifest $manifest -Entry $entry) {
                    Write-Host ""
                }
            } else {
                if (Invoke-ManifestDisable -Manifest $manifest -Entry $entry) {
                    Write-Host ""
                }
            }
        }
    }
    "revert" {
        Write-Host ""
        Write-Host "  Plugin Deployment :: revert" -ForegroundColor Cyan
        Write-Host "  $('-' * 32)"          -ForegroundColor DarkGray
        # Force link=false for every non-ignored entry, then reconcile. The per-drop
        # ShouldProcess is inside Invoke-SafeAction, so -WhatIf propagates there.
        $revertEntries = $entries | ForEach-Object {
            [PSCustomObject]@{
                name     = $_.name
                link     = $false
                ignore   = $_.ignore
                from     = $_.from
                to       = $_.to
                mappings = $_.mappings
                method   = $_.method
            }
        }

        # Process steps first (so files are not locked when we drop links).
        foreach ($entry in $revertEntries) {
            $manifest = Get-PluginManifest -Name $entry.name -ManifestDir $manifestDir
            if ($null -eq $manifest) { continue }
            if (Invoke-ManifestProcessSteps -Manifest $manifest -Entry $entry) {
                Write-Host ""
            }
        }

        $delta = Build-Delta -EntryList $revertEntries
        Invoke-Reconcile -Delta $delta -Force:$Force

        # Reg-disable after link drop.
        foreach ($entry in $revertEntries) {
            $manifest = Get-PluginManifest -Name $entry.name -ManifestDir $manifestDir
            if ($null -eq $manifest) { continue }
            if (Invoke-ManifestDisable -Manifest $manifest -Entry $entry) {
                Write-Host ""
            }
        }
    }
    "adopt" {
        Write-Host ""
        Write-Host "  Plugin Deployment :: adopt" -ForegroundColor Cyan
        Write-Host "  $('-' * 32)"          -ForegroundColor DarkGray
        if (-not $PSCmdlet.ShouldProcess($stateFile, "Adopt: scan system and overwrite state.json")) {
            # WhatIf mode: still scan and report, but don't write.
            Write-Host "  (WhatIf: scan would happen, no file written)" -ForegroundColor DarkGray
            return
        }
        $newState = Invoke-Adopt -PluginRoot $pluginRoot -StateFile $stateFile
        $linked   = ($newState.plugins | Where-Object { $_.Link }).Count
        $unlinked = ($newState.plugins | Where-Object { -not $_.Link }).Count
        Write-Host ("  Discovered {0} plugins; wrote {1}" -f $newState.plugins.Count, $stateFile) -ForegroundColor Green
        Write-Host ("    linked:   {0}" -f $linked)   -ForegroundColor Cyan
        Write-Host ("    unlinked: {0}" -f $unlinked) -ForegroundColor DarkGray
    }
    "snapshot" {
        Write-Host ""
        Write-Host "  Plugin Deployment :: snapshot" -ForegroundColor Cyan
        Write-Host "  $('-' * 32)"              -ForegroundColor DarkGray
        $delta = Build-Delta -EntryList $entries
        Save-Snapshot -Path $snapshotFile -Delta $delta | Out-Null
        Write-Host ("  Saved snapshot: {0}" -f $snapshotFile) -ForegroundColor DarkGray
    }
    "status" {
        # Read-only: probe what exists now and diff it against the last snapshot.
        # Deliberately does not write a snapshot -- that would move the baseline
        # and hide the very drift the user asked to see.
        Write-Host ""
        Write-Host "  Plugin Deployment :: status" -ForegroundColor Cyan
        Write-Host "  $('-' * 32)"           -ForegroundColor DarkGray

        if (-not (Test-Path -LiteralPath $snapshotFile)) {
            Write-Host ""
            Write-Host "  No baseline: $snapshotFile does not exist yet." -ForegroundColor Yellow
            Write-Host "  Run 'snapshot' or 'plan' first to record one." -ForegroundColor DarkGray
            exit 0
        }

        $baseline = $null
        try {
            $baseline = Get-Content -Raw -LiteralPath $snapshotFile | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Host ""
            Write-Host "  Baseline unreadable: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }

        # Probe current state without Compare-State -- we want raw observation,
        # not an action verdict against a desired state.
        $observed = @()
        foreach ($entry in $entries) {
            $observed += Get-SymlinkEntryState -Entry $entry
        }

        $changes = Get-StateDrift -Current $observed -Baseline $baseline

        Write-Host ""
        if ($changes.Count -eq 0) {
            Write-Host "  No drift since $(Split-Path -Leaf $snapshotFile)." -ForegroundColor Green
            exit 0
        }

        Write-Host "  Drift detected since last snapshot:" -ForegroundColor Yellow
        foreach ($c in $changes) {
            $color = switch ($c.change) {
                'added'      { 'Green' }
                'removed'    { 'DarkCyan' }
                'retargeted' { 'Yellow' }
                'orphaned'   { 'Red' }
                default      { 'White' }
            }
            $icon = switch ($c.change) {
                'added'      { '+' }
                'removed'    { '-' }
                'retargeted' { '~' }
                'orphaned'   { '!' }
                default      { '?' }
            }
            $detail = switch ($c.change) {
                'added'      { "was absent, now $($c.now.kind)" }
                'removed'    { "was $($c.prev), now absent" }
                'retargeted' { "$($c.prev) -> $($c.now)" }
                'orphaned'   { "still present, no longer declared ($($c.prev))" }
                default      { '' }
            }
            Write-Host ("  {0} {1,-11} {2}" -f $icon, $c.change, $c.to) -ForegroundColor $color
            if ($detail) { Write-Host ("      {0}" -f $detail) -ForegroundColor DarkGray }
        }
        Write-Host ""
        Write-Host ("  Total changes: {0}" -f $changes.Count) -ForegroundColor Cyan
        exit 0
    }
}

exit 0

