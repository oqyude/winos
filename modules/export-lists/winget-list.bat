@echo off

set "init=%~dp0\..\init.bat"
call %init%

winget export -o "%packages-user-lists%\winget.json" -s "winget" --include-versions