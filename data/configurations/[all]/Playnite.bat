@echo off
setlocal

set "app=Playnite"

set "from_1=%storage%\%app%"
set "to_1=%appdata%\%app%"

rd /q "%to_1%"

mklink /D "%to_1%" "%from_1%"
endlocal