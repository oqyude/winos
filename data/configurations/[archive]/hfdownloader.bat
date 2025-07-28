@echo off
setlocal

set "app=xdg-configs"

set "from_1=%storage%\%app%"
set "to_1=%userprofile%\.config"

rd /q "%to_1%"

mklink /D "%to_1%" "%from_1%"
endlocal