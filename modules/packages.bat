::@echo off
setlocal

cd /d "%~dp0"
call init.bat

::powershell -ExecutionPolicy Bypass -File "%chocolatey%"

for %%f in ("%packages-any%\*.bat") do (
    echo Running %%f
    call "%%f"
)
for %%f in ("%packages-user%\*.bat") do (
    echo Running %%f
    call "%%f"
)
endlocal