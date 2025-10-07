$initFile = Join-Path $PSScriptRoot ".\settings\init.ps1"
. $initFile

# run.ps1 — проверка прав администратора
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Скрипт требует права администратора. Перезапуск..."
    
    # Перезапуск скрипта с правами админа
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Если админ — продолжаем
Write-Host "Запуск от имени администратора подтвержден."

# Аргумент действия
$action = if ($args.Count -ge 1) { $args[0] } else { "reconnect" }

# Вызов apps-manager.ps1 с передачей аргумента
$appsManager = Join-Path $PSScriptRoot "apps-manager.ps1"
. $appsManager $action