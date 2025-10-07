# Переходим в папку скрипта
Set-Location -Path $PSScriptRoot

# Определяем root аналогично %~dp0..\ 
$root = Join-Path $PSScriptRoot ".."

# Подключаем vars.ps1
$varsFile = Join-Path $root "settings\vars.ps1"
if (Test-Path $varsFile) {
    . $varsFile   # точка + пробел = source / импорт
} else {
    Write-Warning "Vars file not found: $varsFile"
}
