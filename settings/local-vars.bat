::@echo off

:: Внешние переменные путей
set "vars=%~dp0vars.bat"

:: Пакетные менеджеры
set "chocolatey=%~dp0chocolatey.ps1"
set "scoop=%~dp0\scoop\scoop.ps1"

:: Пакеты
set "packages=%~dp0..\packages"
:: Конфигурации
set "configurations=%~dp0..\configurations"