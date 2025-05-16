@echo off
setlocal

set "init=%~dp0\..\settings\init.bat"
call %init%

if not exist "%packages-user-lists%" (
    mkdir "%packages-user-lists%"
)

:choco-list
start cmd /c choco export "%packages-user-lists%\choco.config" --include-version-numbers

:msstore-list
start cmd /c winget export -o "%packages-user-lists%\msstore.json" -s "msstore" --include-versions

:winget-list
start cmd /c winget export -o "%packages-user-lists%\winget.json" -s "winget" --include-versions

endlocal
exit /B