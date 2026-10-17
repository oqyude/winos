# process-kill.ps1 -- Run a script (typically .cmd or .ps1) before destructive ops.
#
# Used by plugin manifests' Process array, e.g.:
#   Process = @(
#       @{ BeforeRevert = "R2R\R2R_Kill_Waves_Background_Process.cmd" }
#   )
#
# The script runs in the plugin's root directory (so it can find relative paths
# like R2R\kill.exe). Exit code 0 = success; non-zero is reported but does not
# abort the rest of the apply/revert (other steps still run).

function Invoke-ProcessScript {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string]$ScriptPath,
        [Parameter(Mandatory)] [string]$WorkDir
    )

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        Write-Warning "Process script not found: $ScriptPath"
        return [PSCustomObject]@{ Status = 'skipped'; Note = 'script not found' }
    }

    if (-not $PSCmdlet.ShouldProcess($ScriptPath, "Run process script")) {
        return [PSCustomObject]@{ Status = 'skipped'; Note = 'WhatIf' }
    }

    $ext = [System.IO.Path]::GetExtension($ScriptPath).ToLower()
    $workDirParent = Split-Path -Parent $ScriptPath
    $effectiveWorkDir = if ($workDirParent) { $workDirParent } else { $WorkDir }

    Push-Location -LiteralPath $effectiveWorkDir -ErrorAction SilentlyContinue
    try {
        $stderr = $null
        $code = 0
        if ($ext -eq '.ps1') {
            $stderr = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath 2>&1
            $code = $LASTEXITCODE
        } elseif ($ext -eq '.cmd' -or $ext -eq '.bat') {
            $stderr = & cmd.exe /c $ScriptPath 2>&1
            $code = $LASTEXITCODE
        } else {
            $stderr = & $ScriptPath 2>&1
            $code = $LASTEXITCODE
        }

        if ($code -eq 0) {
            return [PSCustomObject]@{ Status = 'invoked'; Note = "exit 0" }
        } else {
            return [PSCustomObject]@{ Status = 'failed'; Note = "exit ${code}: ${stderr}" }
        }
    } catch {
        return [PSCustomObject]@{ Status = 'failed'; Note = $_.Exception.Message }
    } finally {
        Pop-Location -ErrorAction SilentlyContinue
    }
}
