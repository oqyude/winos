# State.ps1 — Probe actual state of symlink-manager targets
# Pure functions; no side effects.

function Get-SymlinkSubState {
    <#
    .SYNOPSIS
        Probe actual state of a single (from, to) pair.
    .DESCRIPTION
        Returns a PSCustomObject describing the target's state:
        - exists: bool
        - kind: 'missing' | 'symlink' | 'file' | 'directory' | 'broken-symlink'
        - target: actual symlink target (or $null)
        - matches: bool — true if symlink target equals expected source
    .PARAMETER From
        Expected source path (where symlink should point).
    .PARAMETER To
        Target path to probe.
    #>
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

    # Symlink: ReparsePoint attribute set
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

    # Not a symlink — file or directory
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

function Resolve-EntryPath {
    <#
    .SYNOPSIS
        Expand $persist, $env:USERPROFILE and other vars in entry's from/to paths.
    .DESCRIPTION
        Returns PSCustomObject with resolved From and To paths.
    #>
    param(
        [Parameter(Mandatory)] $Entry
    )

    $rawFrom = $Entry.from
    $rawTo   = $Entry.to

    # Substitute $name with entry's name (existing convention)
    $rawFrom = $rawFrom -replace '\$name', $Entry.name
    $rawTo   = $rawTo   -replace '\$name', $Entry.name

    $resolvedFrom = if ($rawFrom) { $ExecutionContext.InvokeCommand.ExpandString($rawFrom) } else { $null }
    $resolvedTo   = if ($rawTo)   { $ExecutionContext.InvokeCommand.ExpandString($rawTo) }   else { $null }

    [PSCustomObject]@{
        From = $resolvedFrom
        To   = $resolvedTo
    }
}

function Get-SymlinkEntryState {
    <#
    .SYNOPSIS
        Probe actual state for all (from, to) pairs in an entry.
    #>
    param(
        [Parameter(Mandatory)] $Entry
    )

    $resolved = Resolve-EntryPath -Entry $Entry
    $subentries = @()

    if ($Entry.mappings -and $Entry.mappings.Count -gt 0) {
        foreach ($m in $Entry.mappings) {
            if ($null -eq $m -or -not $m.from) { continue }
            $src = if ($resolved.From) { Join-Path $resolved.From $m.from } else { $null }
            $dst = if ($resolved.To)   { Join-Path $resolved.To   $m.to }   else { $null }
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

function Compare-State {
    <#
    .SYNOPSIS
        Categorize each subentry into an action: noop | create | replace | drop | conflict.
    .DESCRIPTION
        For desired='symlink' (enabled=true):
          - noop:     exists=true, kind=symlink, matches=true
          - create:   exists=false
          - replace:  exists=true, kind=symlink, matches=false (drift)
          - replace:  exists=true, kind=broken-symlink
          - conflict: exists=true, kind=file or kind=directory

        For desired='missing' (enabled=false):
          - noop:     exists=false (target already absent)
          - drop:     exists=true (any kind) — break the connection
    .PARAMETER EntryState
        Output from Get-SymlinkEntryState.
    .PARAMETER Desired
        Desired state of the target:
          - 'symlink': target should be a symlink to the source
          - 'missing': target should not exist (break connection)
    #>
    param(
        [Parameter(Mandatory)] $EntryState,
        [ValidateSet('symlink', 'missing')]
        [string]$Desired = 'symlink'
    )

    foreach ($sub in $EntryState.subentries) {
        if ($Desired -eq 'missing') {
            # enabled=false: target should not exist
            $action = if ($sub.state.kind -eq 'missing') { 'noop' } else { 'drop' }
        } else {
            # enabled=true: target should be a symlink to source
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

function Invoke-SafeAction {
    <#
    .SYNOPSIS
        Apply safe (or forced) actions for symlink entries.
    .DESCRIPTION
        Without -Force: skip replace and conflict (safe mode).
        With -Force: execute replace (drifted symlink) and conflict (file/dir in the way).
    .PARAMETER EntryState
        Output from Compare-State.
    .PARAMETER Force
        Overwrite existing targets that differ or are regular files/directories.
    #>
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
                if ($PSCmdlet.ShouldProcess($sub.to, "Create symlink to $($sub.from)")) {
                    try {
                        $parent = Split-Path -Parent $sub.to
                        if (-not (Test-Path $parent)) {
                            New-Item -ItemType Directory -Path $parent -Force | Out-Null
                        }
                        New-Item -ItemType SymbolicLink -Path $sub.to -Value $sub.from -Force -ErrorAction Stop | Out-Null
                        $results += [PSCustomObject]@{
                            action = 'create'
                            from   = $sub.from
                            to     = $sub.to
                            status = 'created'
                            note   = $null
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
                if ($Force -and $PSCmdlet.ShouldProcess($sub.to, "Force-replace symlink to $($sub.from)")) {
                    try {
                        Remove-Item -LiteralPath $sub.to -Recurse -Force
                        $parent = Split-Path -Parent $sub.to
                        if (-not (Test-Path $parent)) {
                            New-Item -ItemType Directory -Path $parent -Force | Out-Null
                        }
                        New-Item -ItemType SymbolicLink -Path $sub.to -Value $sub.from -Force -ErrorAction Stop | Out-Null
                        $results += [PSCustomObject]@{
                            action = 'replace'
                            from   = $sub.from
                            to     = $sub.to
                            status = 'replaced'
                            note   = $null
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
                if ($PSCmdlet.ShouldProcess($sub.to, "Remove (enabled=false)")) {
                    try {
                        $item = Get-Item -LiteralPath $sub.to -Force -ErrorAction SilentlyContinue
                        if ($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                            # Symlink: remove just the link, do not follow
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
                if ($Force -and $PSCmdlet.ShouldProcess($sub.to, "Force-overwrite with symlink to $($sub.from)")) {
                    try {
                        Remove-Item -LiteralPath $sub.to -Recurse -Force
                        $parent = Split-Path -Parent $sub.to
                        if (-not (Test-Path $parent)) {
                            New-Item -ItemType Directory -Path $parent -Force | Out-Null
                        }
                        New-Item -ItemType SymbolicLink -Path $sub.to -Value $sub.from -Force -ErrorAction Stop | Out-Null
                        $results += [PSCustomObject]@{
                            action = 'conflict'
                            from   = $sub.from
                            to     = $sub.to
                            status = 'resolved'
                            note   = $null
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

function Format-Subentry {
    <#
    .SYNOPSIS
        Format a single subentry as a colored status line.
    #>
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

function Format-Plan {
    <#
    .SYNOPSIS
        Render plan as a human-readable table.
    .PARAMETER Delta
        Array of EntryState objects (after Compare-State).
    #>
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

function Save-Snapshot {
    <#
    .SYNOPSIS
        Save a snapshot of the current state to JSON.
    .PARAMETER Path
        Output file path.
    .PARAMETER Delta
        Output from Compare-State.
    #>
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
        tool_version   = '1.0.0'
        entries        = $Delta
    }

    $snapshot | ConvertTo-Json -Depth 10 | Out-File -FilePath $Path -Encoding utf8
    $snapshot
}
