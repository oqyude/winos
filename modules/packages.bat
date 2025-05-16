@echo off
setlocal

set "init=%~dp0\..\settings\init.bat"
call %init%

where choco >nul 2>nul
if %errorlevel% neq 0 (
    echo Chocolatey installing...
    powershell -ExecutionPolicy Bypass -File "%chocolatey%"
) else (
    echo Chocolatey has already installed.
)

call %packages-installer%

endlocal