@echo off
setlocal

set "init=%~dp0\..\settings\init.bat"
call %init%

for %%f in ("test\*.bat") do (
    echo Running %%f
    call "%%f"
)

endlocal