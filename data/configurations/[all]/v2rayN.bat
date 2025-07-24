@echo off
setlocal

set "app=v2rayN"

set "from_1=%storage%\%app%"
set "to_1=%localappdata%\%app%"

rd /q "%to_1%"

mklink /D "%to_1%" "%from_1%"
endlocal