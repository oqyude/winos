# Verify.ps1 -- Read-only pre-flight check over the entries state.json selects.
#
# Pure: no writes, no links, no registry, no filesystem changes. It only asks
# whether the paths apply or revert are about to touch actually exist.
#
# Scope differs from scripts/audit-plugins.ps1, which sweeps the whole library.
# This covers exactly what state.json selects, resolved the way Resolve-EntryMaps
# resolves it at run time, so a divergence between what verify accepts and what
# apply does is visible before leaving the sandbox.

function Get-VerifyReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Entries,
        [Parameter(Mandatory)] [string]$PluginRoot,
        [Parameter(Mandatory)] [string]$ManifestDir
    )

    $problems = @()
    $checked  = 0

    foreach ($entry in $Entries) {
        $pluginDir = Join-Path $PluginRoot $entry.name

        # Link sources, already absolute by the time they arrive.
        #
        # Nulls are filtered before counting. An absent mappings property arrives
        # as $null, and @($null) is a one-element array, so a bare
        # @($entry.mappings).Count -eq 0 would silently skip this check.
        $mappings = @($entry.mappings | Where-Object { $null -ne $_ })
        if ($mappings.Count -eq 0 -and -not $entry.from) {
            $problems += [PSCustomObject]@{
                Kind = 'NO_MAPPINGS'; Plugin = $entry.name
                Detail = 'no links resolved and no manifest'
            }
        }
        foreach ($m in $mappings) {
            $checked++
            if (-not (Test-Path -LiteralPath $m.From)) {
                $problems += [PSCustomObject]@{ Kind = 'MISSING_SRC'; Plugin = $entry.name; Detail = $m.From }
            }
        }

        $manifest = Get-PluginManifest -Name $entry.name -ManifestDir $ManifestDir
        if ($null -eq $manifest) { continue }

        # Both directions: an OnDisable file that is absent only fails on revert.
        foreach ($action in @('enable', 'disable')) {
            foreach ($s in (Get-ManifestRegistrySteps -Manifest $manifest -Action $action -BaseDir $pluginDir)) {
                $checked++
                if (-not (Test-Path -LiteralPath $s.RegFile)) {
                    $problems += [PSCustomObject]@{ Kind = 'MISSING_REG'; Plugin = $entry.name; Detail = $s.RegFile }
                }
            }
        }

        foreach ($s in (Get-ManifestProcessSteps -Manifest $manifest -Trigger 'beforeRevert' -BaseDir $pluginDir)) {
            $checked++
            if (-not (Test-Path -LiteralPath $s.Script)) {
                $problems += [PSCustomObject]@{ Kind = 'MISSING_SCRIPT'; Plugin = $entry.name; Detail = $s.Script }
            }
        }

        foreach ($s in (Get-ManifestCopySteps -Manifest $manifest -BaseDir $pluginDir)) {
            $checked++
            if (-not (Test-Path -LiteralPath $s.From -PathType Container)) {
                $problems += [PSCustomObject]@{ Kind = 'MISSING_COPY_SRC'; Plugin = $entry.name; Detail = $s.From }
            }
        }
    }

    [PSCustomObject]@{ Problems = $problems; Checked = $checked }
}