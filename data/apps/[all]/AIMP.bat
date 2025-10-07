@echo off
setlocal

set "app=AIMP"

set "from_1=%storage%\%app%"
set "to_1=%appdata%\%app%"

if "%1"=="" goto reconnect
if /I "%1"=="disconnect" goto disconnect
if /I "%1"=="connect" goto connect

:disconnect
rd /Q "%to_1%"
goto end

:connect
mklink /D "%to_1%" "%from_1%"
goto end

:reconnect
rd /Q "%to_1%"
mklink /D "%to_1%" "%from_1%"
goto end

:end
endlocal