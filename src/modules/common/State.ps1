# State.ps1 -- Probe, compare, and reconcile symlink state.
#
# Pure functions for state analysis; side-effecting Invoke-SafeAction for execution.
# Used by src/modules/plugin-manager.ps1.
#
# Concurrency: none of these functions share mutable state. Multiple instances
# can probe the same target safely.
#
# Junction note: we use New-Item -ItemType Junction (not SymbolicLink) so
# running as non-admin works on Windows. Junctions and symlinks both set
# ReparsePoint; Get-SymlinkSubState treats them the same.

# Get-SymlinkSubState -- Probe actual state of a single (from, to) pair.
#
# Returns a PSCustomObject describing the target's state:
#   - exists: bool
#   - kind: 'missing' | 'symlink' | 'file' | 'directory' | 'broken-symlink'
#   - target: actual symlink target (or $null)
#   - matches: bool -- true if symlink target equals expected source
function Get-SymlinkSubState {
    param(
        [Parameter(Mandatory)] [string]$From,
        [Parameter(Mandatory)] [string]$To
    )

    if (-not (Test-Path -LiteralPath $To)) {
        return [PSCustomObject]@{
            exists  = $false
            kind    = 'missing'
            target  = $null
            matches = $false
        }
    }

    $item = Get-Item -LiteralPath $To -Force -ErrorAction SilentlyContinue
    if (-not $item) {
        return [PSCustomObject]@{
            exists  = $false
            kind    = 'missing'
            target  = $null
            matches = $false
        }
    }

    # Symlink or junction: ReparsePoint attribute set
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        $actualTarget = $item.Target
        # Check if the symlink target equals expected source (case-insensitive on Windows)
        $targetMatches = ($actualTarget -and $From -and
                    [string]::Equals($actualTarget.TrimEnd('\', '/'),
                                     $From.TrimEnd('\', '/'),
                                     [System.StringComparison]::OrdinalIgnoreCase))
        # Determine if symlink is broken (target doesn't exist)
        if ($actualTarget -and -not (Test-Path -LiteralPath $actualTarget)) {
            return [PSCustomObject]@{
                exists  = $true
                kind    = 'broken-symlink'
                target  = $actualTarget
                matches = $targetMatches
            }
        }
        return [PSCustomObject]@{
            exists  = $true
            kind    = 'symlink'
            target  = $actualTarget
            matches = $targetMatches
        }
    }

    # Not a symlink -- file or directory
    if ($item.PSIsContainer) {
        return [PSCustomObject]@{
            exists  = $true
            kind    = 'directory'
            target  = $null
            matches = $false
        }
    }

    return [PSCustomObject]@{
        exists  = $true
        kind    = 'file'
        target  = $null
        matches = $false
    }
}

# Resolve-EntryPath -- Expand $pluginRoot, $env:USERPROFILE and other vars in entry's from/to paths.
#
# Returns PSCustomObject with resolved From and To paths.
function Resolve-EntryPath {
    param(
        [Parameter(Mandatory)] $Entry
    )

    $rawFrom = $Entry.from
    $rawTo   = $Entry.to

    # Substitute $name with entry's name
    $rawFrom = $rawFrom -replace '\$name', $Entry.name
    $rawTo   = $rawTo   -replace '\$name', $Entry.name

    $resolvedFrom = if ($rawFrom) { $ExecutionContext.InvokeCommand.ExpandString($rawFrom) } else { $null }
    $resolvedTo   = if ($rawTo)   { $ExecutionContext.InvokeCommand.ExpandString($rawTo)   } else { $null }

    [PSCustomObject]@{
        From = $resolvedFrom
        To   = $resolvedTo
    }
}

# Get-SymlinkEntryState -- Probe actual state for all (from, to) pairs in an entry.
#
# Two mappings schemas are supported:
#   - Legacy: entry has top-level from/to; mappings' from/to are RELATIVE sub-paths.
#   - New:    entry has no top-level from/to; mappings' from/to are ABSOLUTE paths.
# In the new schema, the mapping is used as-is; in the legacy schema, mapping paths
# are joined onto the resolved entry paths.
function Get-SymlinkEntryState {
    param(
        [Parameter(Mandatory)] $Entry
    )

    $resolved = Resolve-EntryPath -Entry $Entry
    $subentries = @()

    if ($Entry.mappings -and $Entry.mappings.Count -gt 0) {
        foreach ($m in $Entry.mappings) {
            if ($null -eq $m -or -not $m.from) { continue }
            # If entry has top-level from/to, treat mapping paths as relative.
            # Otherwise use them as absolute.
            $src = if ($resolved.From) { Join-Path $resolved.From $m.from } else { $m.from }
            $dst = if ($resolved.To)   { Join-Path $resolved.To   $m.to   } else { $m.to }
            if (-not $src -or -not $dst) { continue }
            $state = Get-SymlinkSubState -From $src -To $dst
            $subentries += [PSCustomObject]@{
                from   = $src
                to     = $dst
                state  = $state
            }
        }
    } else {
        # Single symlink (no mappings)
        if ($resolved.From -and $resolved.To) {
            $state = Get-SymlinkSubState -From $resolved.From -To $resolved.To
            $subentries += [PSCustomObject]@{
                from   = $resolved.From
                to     = $resolved.To
                state  = $state
            }
        }
    }

    [PSCustomObject]@{
        name      = $Entry.name
        method    = if ($Entry.method) { $Entry.method } else { 'symlink' }
        from      = $resolved.From
        to        = $resolved.To
        subentries = $subentries
    }
}

# Compare-State -- Categorize each subentry into an action: noop | create | replace | drop | conflict.
#
# For desired='symlink' (link=true):
#   - noop:     exists=true, kind=symlink, matches=true
#   - create:   exists=false
#   - replace:  exists=true, kind=symlink, matches=false (drift)
#   - replace:  exists=true, kind=broken-symlink
#   - conflict: exists=true, kind=file or kind=directory
#
# For desired='missing' (link=false):
#   - noop:     exists=false (target already absent)
#   - drop:     exists=true (any kind) -- break the connection
function Compare-State {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $EntryState,
        [ValidateSet('symlink', 'missing')]
        [string]$Desired = 'symlink'
    )

    foreach ($sub in $EntryState.subentries) {
        if ($Desired -eq 'missing') {
            $action = if ($sub.state.kind -eq 'missing') { 'noop' } else { 'drop' }
        } else {
            $action = switch ($sub.state.kind) {
                'missing'        { 'create' }
                'symlink'        { if ($sub.state.matches) { 'noop' } else { 'replace' } }
                'broken-symlink' { 'replace' }
                'file'           { 'conflict' }
                'directory'      { 'conflict' }
                default          { 'conflict' }
            }
        }
        $sub | Add-Member -NotePropertyName 'action' -NotePropertyValue $action -Force
    }

    $EntryState
}

# Invoke-SafeAction -- Apply safe (or forced) actions for symlink entries.
#
# Without -Force: skip replace and conflict (safe mode).
# With -Force: execute replace (drifted symlink) and conflict (file/dir in the way).
#
# Junction type: New-Item -ItemType Junction (not SymbolicLink) -- no admin required.
function Invoke-SafeAction {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] $EntryState,
        [switch]$Force
    )

    $results = @()
    foreach ($sub in $EntryState.subentries) {
        switch ($sub.action) {
            'noop' {
                $results += [PSCustomObject]@{
                    action = 'noop'
                    from   = $sub.from
                    to     = $sub.to
                    status = 'skipped'
                    note   = 'already correct'
                }
            }
            'create' {
                if (-not (Test-Path -LiteralPath $sub.from)) {
                    # Refuse rather than create a link to nothing. Junction and
                    # SymbolicLink both accept a target that does not exist, so a
                    # typo in a manifest would otherwise scatter broken links across
                    # the system and only surface when a DAW fails to load a plugin.
                    $results += [PSCustomObject]@{
                        action = 'create'
                        from   = $sub.from
                        to     = $sub.to
                        status = 'failed'
                        note   = 'source does not exist'
                    }
                    continue
                }
                if ($PSCmdlet.ShouldProcess($sub.to, "Create link to $($sub.from)")) {
                    try {
                        $parent = Split-Path -Parent $sub.to
                        if (-not (Test-Path $parent)) {
                            New-Item -ItemType Directory -Path $parent -Force | Out-Null
                        }
                        $linkType = if (Test-Path -LiteralPath $sub.from -PathType Container) {
                            # Directory: use Junction (no admin required, locally scoped)
                            'Junction'
                        } else {
                            # File: use SymbolicLink
                            'SymbolicLink'
                        }
                        New-Item -ItemType $linkType -Path $sub.to -Value $sub.from -Force -ErrorAction Stop | Out-Null
                        $results += [PSCustomObject]@{
                            action = 'create'
                            from   = $sub.from
                            to     = $sub.to
                            status = 'created'
                            note   = $linkType
                        }
                    } catch {
                        $results += [PSCustomObject]@{
                            action = 'create'
                            from   = $sub.from
                            to     = $sub.to
                            status = 'failed'
                            note   = $_.Exception.Message
                        }
                    }
                }
            }
            'replace' {
                if (-not (Test-Path -LiteralPath $sub.from)) {
                    $results += [PSCustomObject]@{
                        action = 'replace'
                        from   = $sub.from
                        to     = $sub.to
                        status = 'failed'
                        note   = 'source does not exist'
                    }
                    continue
                }
                if ($Force -and $PSCmdlet.ShouldProcess($sub.to, "Force-replace link to $($sub.from)")) {
                    try {
                        Remove-Item -LiteralPath $sub.to -Recurse -Force
                        $parent = Split-Path -Parent $sub.to
                        if (-not (Test-Path $parent)) {
                            New-Item -ItemType Directory -Path $parent -Force | Out-Null
                        }
                        $linkType = if (Test-Path -LiteralPath $sub.from -PathType Container) {
                            'Junction'
                        } else {
                            'SymbolicLink'
                        }
                        New-Item -ItemType $linkType -Path $sub.to -Value $sub.from -Force -ErrorAction Stop | Out-Null
                        $results += [PSCustomObject]@{
                            action = 'replace'
                            from   = $sub.from
                            to     = $sub.to
                            status = 'replaced'
                            note   = $linkType
                        }
                    } catch {
                        $results += [PSCustomObject]@{
                            action = 'replace'
                            from   = $sub.from
                            to     = $sub.to
                            status = 'failed'
                            note   = $_.Exception.Message
                        }
                    }
                } else {
                    $results += [PSCustomObject]@{
                        action = 'replace'
                        from   = $sub.from
                        to     = $sub.to
                        status = 'skipped'
                        note   = 'drift, --force required'
                    }
                }
            }
            'drop' {
                if ($PSCmdlet.ShouldProcess($sub.to, "Remove (link=false)")) {
                    try {
                        $item = Get-Item -LiteralPath $sub.to -Force -ErrorAction SilentlyContinue
                        if ($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                            # Junction or symlink: remove just the link, do not follow
                            $item.Delete()
                        } else {
                            # Regular file/dir: explicit remove
                            Remove-Item -LiteralPath $sub.to -Recurse -Force
                        }
                        $results += [PSCustomObject]@{
                            action = 'drop'
                            from   = $sub.from
                            to     = $sub.to
                            status = 'removed'
                            note   = $null
                        }
                    } catch {
                        $results += [PSCustomObject]@{
                            action = 'drop'
                            from   = $sub.from
                            to     = $sub.to
                            status = 'failed'
                            note   = $_.Exception.Message
                        }
                    }
                }
            }
            'conflict' {
                if ($Force -and $PSCmdlet.ShouldProcess($sub.to, "Force-overwrite with link to $($sub.from)")) {
                    try {
                        Remove-Item -LiteralPath $sub.to -Recurse -Force
                        $parent = Split-Path -Parent $sub.to
                        if (-not (Test-Path $parent)) {
                            New-Item -ItemType Directory -Path $parent -Force | Out-Null
                        }
                        $linkType = if (Test-Path -LiteralPath $sub.from -PathType Container) {
                            'Junction'
                        } else {
                            'SymbolicLink'
                        }
                        New-Item -ItemType $linkType -Path $sub.to -Value $sub.from -Force -ErrorAction Stop | Out-Null
                        $results += [PSCustomObject]@{
                            action = 'conflict'
                            from   = $sub.from
                            to     = $sub.to
                            status = 'resolved'
                            note   = $linkType
                        }
                    } catch {
                        $results += [PSCustomObject]@{
                            action = 'conflict'
                            from   = $sub.from
                            to     = $sub.to
                            status = 'failed'
                            note   = $_.Exception.Message
                        }
                    }
                } else {
                    $results += [PSCustomObject]@{
                        action = 'conflict'
                        from   = $sub.from
                        to     = $sub.to
                        status = 'skipped'
                        note   = 'target is regular file/dir, --force required'
                    }
                }
            }
        }
    }

    $results
}

# Format-Subentry -- Format a single subentry as a colored status line.
function Format-Subentry {
    param($Sub)

    $icon = switch ($Sub.action) {
        'noop'     { '~' }
        'create'   { '+' }
        'replace'  { '*' }
        'drop'     { '-' }
        'conflict' { '!' }
        default    { '?' }
    }

    $color = switch ($Sub.action) {
        'noop'     { 'DarkGray' }
        'create'   { 'Green' }
        'replace'  { 'Yellow' }
        'drop'     { 'DarkCyan' }
        'conflict' { 'Red' }
        default    { 'White' }
    }

    $fromShort = if ($Sub.from.Length -gt 50) { '...' + $Sub.from.Substring($Sub.from.Length - 47) } else { $Sub.from }
    Write-Host ("  {0} {1,-20} {2,-10} {3}" -f $icon, $Sub.action, $Sub.state.kind, $fromShort) -ForegroundColor $color
}

# Format-Plan -- Render plan as a human-readable table.
function Format-Plan {
    param([Parameter(Mandatory)] $Delta)

    $summary = @{
        noop     = 0
        create   = 0
        replace  = 0
        drop     = 0
        conflict = 0
    }
    $totalSubentries = 0

    foreach ($entry in $Delta) {
        if ($entry.method -ne 'symlink') { continue }
        Write-Host ""
        Write-Host ("{0} ({1} subentries, {2})" -f $entry.name, $entry.subentries.Count, $entry.method) -ForegroundColor Cyan
        foreach ($sub in $entry.subentries) {
            Format-Subentry -Sub $sub
            if ($summary.ContainsKey($sub.action)) {
                $summary[$sub.action]++
            }
            $totalSubentries++
        }
    }

    Write-Host ""
    Write-Host "=== Summary ===" -ForegroundColor Cyan
    Write-Host ("Total sub-entries: {0}" -f $totalSubentries)
    Write-Host ("  ~ noop:     {0}" -f $summary.noop)   -ForegroundColor DarkGray
    Write-Host ("  + create:   {0}" -f $summary.create) -ForegroundColor Green
    Write-Host ("  * replace:  {0}" -f $summary.replace) -ForegroundColor Yellow
    Write-Host ("  - drop:     {0}" -f $summary.drop)   -ForegroundColor DarkCyan
    Write-Host ("  ! conflict: {0}" -f $summary.conflict) -ForegroundColor Red

    return $summary
}

# Get-StateDrift -- Diff observed state against a previously saved snapshot.
#
# Pure function: no side effects, no I/O. Takes the entry-state objects that
# Get-SymlinkEntryState produces plus a deserialized snapshot, and returns the
# list of things that changed:
#
#   added      -- target exists now, baseline had no record of it (or had it absent)
#   removed    -- baseline recorded it present, it is gone now
#   retargeted -- both are links, but they point somewhere different
#   orphaned   -- baseline recorded it present, and nothing probes it any more
#                 (usually the plugin was dropped from state.json since)
#
# Comparing by target path rather than by index keeps the diff stable when
# plugins are reordered in state.json between runs.
function Get-StateDrift {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Current,
        [Parameter(Mandatory)] $Baseline
    )

    # Index the baseline by target path.
    $known = @{}
    if ($null -ne $Baseline -and $Baseline.PSObject.Properties['entries']) {
        foreach ($e in $Baseline.entries) {
            if ($null -eq $e) { continue }
            if (-not $e.PSObject.Properties['subentries']) { continue }
            foreach ($s in $e.subentries) {
                if ($null -eq $s -or -not $s.to) { continue }
                $known[$s.to] = $s.state
            }
        }
    }

    $changes = @()
    $seen = @{}

    foreach ($e in $Current) {
        if ($null -eq $e) { continue }
        if (-not $e.PSObject.Properties['subentries']) { continue }
        foreach ($sub in $e.subentries) {
            if ($null -eq $sub -or -not $sub.to) { continue }
            $seen[$sub.to] = $true

            $now  = $sub.state
            $prev = if ($known.ContainsKey($sub.to)) { $known[$sub.to] } else { $null }

            $kind = $null
            if ($null -eq $prev) {
                if ($now.exists) { $kind = 'added' }
            } elseif ($prev.exists -and -not $now.exists) {
                $kind = 'removed'
            } elseif ($prev.exists -and $now.exists -and $prev.kind -eq 'symlink' -and $now.kind -eq 'symlink') {
                if (-not [string]::Equals([string]$prev.target, [string]$now.target, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $kind = 'retargeted'
                }
            }

            if ($null -ne $kind) {
                $changes += [PSCustomObject]@{
                    change = $kind
                    to     = $sub.to
                    from   = $sub.from
                    prev   = if ($null -ne $prev) { $prev.target } else { $null }
                    now    = $now.target
                }
            }
        }
    }

    # Anything the baseline saw that nothing probes any more.
    foreach ($path in $known.Keys) {
        if ($seen.ContainsKey($path)) { continue }
        $prev = $known[$path]
        if ($prev.exists) {
            $changes += [PSCustomObject]@{
                change = 'orphaned'
                to     = $path
                from   = $null
                prev   = $prev.target
                now    = $null
            }
        }
    }

    , $changes
}

# Save-Snapshot -- Save a snapshot of the current state to JSON.
function Save-Snapshot {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] $Delta
    )

    $dataDir = Split-Path -Parent $Path
    if (-not (Test-Path $dataDir)) {
        New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    }

    $snapshot = [PSCustomObject]@{
        timestamp      = (Get-Date).ToString('o')
        tool_version   = $toolVersion
        entries        = $Delta
    }

    $snapshot | ConvertTo-Json -Depth 10 | Out-File -FilePath $Path -Encoding utf8
    $snapshot
}
