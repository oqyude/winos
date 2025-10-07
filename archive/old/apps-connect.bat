@echo off
setlocal
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo Restarting as Admin...
    powershell -Command "Start-Process -FilePath '%~dp0apps-manager.bat' -ArgumentList 'connect' -Verb RunAs"
    exit /b
)

call "%~dp0apps-manager.bat" connect

endlocal