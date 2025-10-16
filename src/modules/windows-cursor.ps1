param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("install","uninstall")]
    [string]$Mode
)

# === Настройки ===
$InfPath = "$Storage\Windows\Cursor\default\Install.inf"
$SchemeName = "W11 Cursors Dark HDPI default (small) by Jepri Creations"
$DefaultScheme = "Windows Aero"

# === Проверка наличия файла ===
if ($Mode -eq "install" -and -not (Test-Path $InfPath)) {
    Write-Host "INF file not found: $InfPath" -ForegroundColor Red
    exit 1
}

# === Функция обновления системных параметров ===
function Refresh-Cursors {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WinAPI {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, string pvParam, uint fWinIni);
}
"@ | Out-Null

    [WinAPI]::SystemParametersInfo(0x0057, 0, $null, 0x01 -bor 0x02) | Out-Null
}

# === Основная логика ===
switch ($Mode) {
    "install" {
        Write-Host "Installing cursor theme..." -ForegroundColor Cyan
        try {
            rundll32.exe setupapi.dll,InstallHinfSection DefaultInstall 132 "$InfPath" | Out-Null
            Set-ItemProperty "HKCU:\Control Panel\Cursors" -Name "(Default)" -Value $SchemeName
            Refresh-Cursors
            Write-Host "Cursor scheme '$SchemeName' installed and applied." -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to install cursor scheme: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    "uninstall" {
        Write-Host "WIP..." -ForegroundColor Cyan
        # Write-Host "Uninstalling cursor theme..." -ForegroundColor Cyan
        # try {
        #     Set-ItemProperty "HKCU:\Control Panel\Cursors" -Name "(Default)" -Value $DefaultScheme
        #     Remove-ItemProperty -Path "HKCU:\Control Panel\Cursors\Schemes" -Name $SchemeName -ErrorAction SilentlyContinue
        #     Refresh-Cursors
        #     Write-Host "Cursor scheme '$SchemeName' removed. Default restored." -ForegroundColor Green
        # }
        # catch {
        #     Write-Host "Failed to uninstall cursor scheme: $($_.Exception.Message)" -ForegroundColor Red
        # }
    }
}

Write-Host "Done." -ForegroundColor White
