<#
.SYNOPSIS
    The canonical file set of the opencode config directory, and the drift
    report around it.

.DESCRIPTION
    The config directory of opencode (~/.config/opencode) accumulates files:
    the installer writes a backup next to every file it rewrites, opencode
    writes its own state there, and a manual experiment leaves a file behind.
    Nothing ever collected them, so two hosts ended up with 13 and 19 files
    for the same installation -- and one of them was MISSING tui.json, which
    nobody noticed because nobody looked at the directory as a whole.

    This file declares the canon: the files that belong there. Everything else
    is drift. The drift is REPORTED, never deleted on the fly -- the installer
    does not touch files it did not write. The one exception is explicit and
    separate: -PruneBackups removes the stale backups, and only those.

    The read functions are pure with respect to the disk: they look at the
    directory and return facts. The only function that writes is
    Invoke-OpenCodeBackupPrune, and it writes only where it is pointed.

.NOTES
    Pure ASCII on purpose: this file travels over ssh to the Windows hosts,
    where a non-ASCII byte in a .ps1 turns into a ParserError.
#>

# The canon: exactly these files belong in the config directory.
#
#   opencode.jsonc           the main config (model, MCP servers, plugins)
#   cli.json                 the plugin declaration for the CLI mode
#   tui.json                 the TUI config (a v1 leftover, kept as it is)
#   oh-my-opencode-slim.json the agent -> model binding
#   package.json             the dependency manifest of the plugin
#   package-lock.json        the pinned dependency tree
#   service.json             written by opencode itself and it holds a secret:
#                            the installer never creates it and never reads it
#
# Everything else in the directory is drift. The list is short on purpose:
# a canon nobody can recite is not a canon.
$OpenCodeCanonicalConfigFiles = @(
    'opencode.jsonc'
    'cli.json'
    'tui.json'
    'oh-my-opencode-slim.json'
    'package.json'
    'package-lock.json'
    'service.json'
)

# The backup patterns the installer writes: "<name>.bak-<yyyyMMdd-HHmmss>".
# Only these two shapes are pruned. A file called "cli.json.bak" or
# "tui.json.v1-legacy.bak" is NOT one of them: it was made by hand, it may
# carry a hand-made state, and the owner has to look at it before it goes.
$OpenCodeBackupPatterns = @('*.bak-*', '*.backup-*')

function Get-OpenCodeCanonicalConfigFiles {
    # The canon, as a copy. A copy, so that a caller cannot change the canon
    # for the next caller by sorting the array it got.
    return @($OpenCodeCanonicalConfigFiles)
}

function Get-OpenCodeConfigDirState {
    # The state of a config directory against the canon.
    #
    # Returns a PSCustomObject:
    #   Path      -- the directory that was looked at
    #   Exists    -- whether it is there at all
    #   Canonical -- the canon
    #   Present   -- the canonical files that are there (in canon order)
    #   Missing   -- the canonical files that are absent (in canon order)
    #   Extra     -- the files that are NOT in the canon (sorted by name)
    #
    # Only FILES are counted. A directory in the config directory is not
    # drift: node_modules is the runtime of the plugin and skills/ is written
    # by opencode when it activates an MCP server. Neither is a file the owner
    # has to think about, and reporting them as drift would bury the real
    # finding (a backup of the config, a file from an abandoned experiment).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $canonical = Get-OpenCodeCanonicalConfigFiles
    $state = [pscustomobject]@{
        Path      = $Path
        Exists    = (Test-Path -LiteralPath $Path -PathType Container)
        Canonical = $canonical
        Present   = @()
        Missing   = @()
        Extra     = @()
    }

    if (-not $state.Exists) { return $state }

    $names = @(Get-ChildItem -LiteralPath $Path -File -ErrorAction SilentlyContinue |
               ForEach-Object { $_.Name })

    $state.Present = @($canonical | Where-Object { $names -contains $_ })
    $state.Missing = @($canonical | Where-Object { $names -notcontains $_ })
    $state.Extra   = @($names | Where-Object { $canonical -notcontains $_ } | Sort-Object)
    return $state
}

function Get-OpenCodeConfigDirCheckState {
    # The state the `config-dir` check reports.
    #
    #   'missing' -- a file of the canon is absent. That is a real gap: the
    #                machine is not the one the registry describes.
    #   'warn'    -- only drift (files outside the canon). A warning: the
    #                installer never deletes a file it did not write, so the
    #                exit code must not change because of it.
    #   'ok'      -- the directory holds exactly the canon.
    #
    # The shape matches the check framework of install-opencode.ps1 (State /
    # Message / Expected / Actual), but it is built here so that this file
    # stays free of any dependency on the installer.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $state = Get-OpenCodeConfigDirState -Path $Path
    if (-not $state.Exists) {
        return [pscustomobject]@{
            State = 'missing'; Message = "the config directory does not exist: $Path"
            Expected = ''; Actual = ''
        }
    }
    if ($state.Missing.Count -gt 0) {
        return [pscustomobject]@{
            State = 'missing'; Message = ('missing from the canon: ' + ($state.Missing -join ', '))
            Expected = ($state.Canonical -join ', '); Actual = ($state.Present -join ', ')
        }
    }
    if ($state.Extra.Count -gt 0) {
        return [pscustomobject]@{
            State = 'warn'; Message = ('files outside the canon: ' + ($state.Extra -join ', '))
            Expected = ($state.Canonical -join ', '); Actual = ($state.Extra -join ', ')
        }
    }
    return [pscustomobject]@{
        State = 'ok'; Message = ''
        Expected = ($state.Canonical -join ', '); Actual = ($state.Present -join ', ')
    }
}

function Get-OpenCodeBackupFile {
    # The backup files of a directory, split by age.
    #
    # Returns a PSCustomObject:
    #   Stale -- the backups older than -OlderThanDays (these are the ones
    #            -PruneBackups removes)
    #   Fresh -- the backups that are younger (these stay)
    #
    # Only the top level of the directory is looked at. The backups are
    # written next to the file they replace, in the config directory itself,
    # and a recursive sweep would reach into node_modules -- which belongs to
    # the plugin, not to the installer.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [int]$OlderThanDays = 14,
        [datetime]$Now = [datetime]::Now
    )

    $result = [pscustomobject]@{
        Path   = $Path
        Cutoff = $Now.AddDays(-$OlderThanDays)
        Stale  = @()
        Fresh  = @()
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $result }

    $backups = @(Get-ChildItem -LiteralPath $Path -File -ErrorAction SilentlyContinue |
                 Where-Object {
                     $name = $_.Name
                     $hit = $false
                     foreach ($pattern in $OpenCodeBackupPatterns) {
                         if ($name -like $pattern) { $hit = $true; break }
                     }
                     $hit
                 })

    $result.Stale = @($backups | Where-Object { $_.LastWriteTime -lt $result.Cutoff })
    $result.Fresh = @($backups | Where-Object { $_.LastWriteTime -ge $result.Cutoff })
    return $result
}

function Invoke-OpenCodeBackupPrune {
    # Removes the stale backups of a directory.
    #
    # -DryRun changes nothing and only reports what WOULD be removed. There is
    # no ShouldProcess here on purpose: the switch that does the deleting is
    # -PruneBackups, it is stated in the command line, and a dry run of it is
    # -DryRun. Two ways to ask the same question is one way too many.
    #
    # Returns a PSCustomObject:
    #   Path    -- the directory that was swept
    #   Cutoff  -- the age limit that was applied
    #   Removed -- the files that were removed (or would be, in a dry run)
    #   Fresh   -- the backups that were kept because they are young
    #   Failed  -- the files that could not be removed
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [int]$OlderThanDays = 14,
        [switch]$DryRun,
        [datetime]$Now = [datetime]::Now
    )

    $backups = Get-OpenCodeBackupFile -Path $Path -OlderThanDays $OlderThanDays -Now $Now
    $removed = New-Object System.Collections.ArrayList
    $failed  = New-Object System.Collections.ArrayList

    foreach ($file in $backups.Stale) {
        if ($DryRun) {
            [void]$removed.Add($file)
            continue
        }
        try {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            [void]$removed.Add($file)
        } catch {
            [void]$failed.Add([pscustomobject]@{ File = $file; Error = $_.Exception.Message })
        }
    }

    return [pscustomobject]@{
        Path    = $Path
        Cutoff  = $backups.Cutoff
        Removed = @($removed)
        Fresh   = @($backups.Fresh)
        Failed  = @($failed)
    }
}
