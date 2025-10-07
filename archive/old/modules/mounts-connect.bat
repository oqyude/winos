@echo off
setlocal

set "init=%~dp0\..\settings\init.bat"
call %init%

for %%f in ("%mounts%\*.bat") do (
    echo Running %%f
    call "%%f"
)
endlocal