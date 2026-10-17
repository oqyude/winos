# copy-tree.ps1 -- Copy a directory tree into a shared location.
#
# Used by plugin manifests' Copy array. This is copy-only, never a mirror:
# copy destinations are shared between vendors, so deleting "extra" files
# would remove another plugin's data. See Invoke-CopyTree for why /MIR was
# removed.
#
# The reverse operation (Remove-CopyTree) is also exposed so the manifest
# can declare a paired cleanup if needed -- but by convention Copy is
# enable-only (no undo), matching the .bat behavior of Waves et al.

# Invoke-CopyTree -- Copy a directory tree into a shared location.
#
# Never deletes. An earlier version used robocopy /MIR, which mirrors: it removes
# anything in the destination that is not in the source. Copy targets are
# shared between vendors -- Waves and u-he both install into
# Common Files\Native Instruments\Service Center -- so mirroring Waves' copy
# silently deleted u-he's preset files. The vendor installers use
# xcopy /S /I /Y, which never deletes, and that is the semantics reproduced
# here with robocopy /E.
function Invoke-CopyTree {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string]$From,
        [Parameter(Mandatory)] [string]$To
    )

    if (-not (Test-Path -LiteralPath $From -PathType Container)) {
        Write-Warning "Copy source missing or not a directory: $From"
        return [PSCustomObject]@{ Status = 'skipped'; Note = 'source missing' }
    }

    # Ensure parent of target exists
    $parent = Split-Path -Parent $To
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        if ($PSCmdlet.ShouldProcess($parent, "Create parent directory")) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
    }

    if (-not $PSCmdlet.ShouldProcess("$From -> $To", "Copy tree (no deletion)")) {
        return [PSCustomObject]@{ Status = 'skipped'; Note = 'WhatIf' }
    }

    # /E copies subdirectories including empty ones. No /MIR and no /PURGE, so
    # files belonging to other vendors in a shared destination are left alone.
    # robocopy exit codes: 0=no change, 1=files copied, 2=extra present in dest
    # (ignored, we never purge), 3+ variants; 8 and above are real failures.
    try {
        $output = robocopy.exe $From $To /E /NFL /NDL /NJH /NJS /NP /R:1 /W:1 2>&1
        $code = $LASTEXITCODE
        if ($code -lt 8) {
            return [PSCustomObject]@{ Status = 'copied'; Note = "robocopy exit $code" }
        } else {
            return [PSCustomObject]@{ Status = 'failed'; Note = "robocopy exit $code" }
        }
    } catch {
        return [PSCustomObject]@{ Status = 'failed'; Note = $_.Exception.Message }
    }
}

function Remove-CopyTree {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [PSCustomObject]@{ Status = 'skipped'; Note = 'not present' }
    }

    if (-not $PSCmdlet.ShouldProcess($Path, "Remove copied tree")) {
        return [PSCustomObject]@{ Status = 'skipped'; Note = 'WhatIf' }
    }

    try {
        Remove-Item -LiteralPath $Path -Recurse -Force
        return [PSCustomObject]@{ Status = 'removed'; Note = $null }
    } catch {
        return [PSCustomObject]@{ Status = 'failed'; Note = $_.Exception.Message }
    }
}
