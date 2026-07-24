[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("install","uninstall")]
    [string]$action
)

# Self-bootstrap: if vars.ps1 hasn't been sourced (run directly), source it.
if (-not $Storage) {
    . (Join-Path $PSScriptRoot "..\init.ps1")
}

# === Cursor API (loaded once per module) ===
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WinAPI {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, string pvParam, uint fWinIni);
}
"@ -ErrorAction SilentlyContinue | Out-Null

# === Настройки ===
$InfPath = "$Storage\Windows\Cursor\default\Install.inf"
$SchemeName = "W11 Cursors Dark HDPI default (small) by Jepri Creations"
$DefaultScheme = "Windows Aero"

function Update-Cursor {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $PSCmdlet.ShouldProcess("SystemParametersInfo", "Refresh cursor theme") | Out-Null
    [WinAPI]::SystemParametersInfo(0x0057, 0, $null, 0x01 -bor 0x02) | Out-Null
}

# === Проверка наличия файла ===
if ($action -eq "install" -and -not (Test-Path $InfPath)) {
    Write-Host "INF file not found: $InfPath" -ForegroundColor Red
    exit 1
}

# === Основная логика ===
switch ($action) {
    "install" {
        Write-Host "Installing cursor theme..." -ForegroundColor Cyan
        try {
            rundll32.exe setupapi.dll,InstallHinfSection DefaultInstall 132 "$InfPath" | Out-Null
            Set-ItemProperty "HKCU:\Control Panel\Cursors" -Name "(Default)" -Value $SchemeName
            Update-Cursor
            Write-Host "Cursor scheme '$SchemeName' installed and applied." -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to install cursor scheme: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    "uninstall" {
        Write-Host "Uninstalling cursor theme..." -ForegroundColor Cyan
        try {
            Set-ItemProperty "HKCU:\Control Panel\Cursors" -Name "(Default)" -Value $DefaultScheme
            Remove-ItemProperty -Path "HKCU:\Control Panel\Cursors\Schemes" -Name $SchemeName -ErrorAction SilentlyContinue
            Update-Cursor
            Write-Host "Cursor scheme reverted to '$DefaultScheme'." -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to uninstall cursor scheme: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host "Done." -ForegroundColor White
