@echo off
setlocal

set "app=beets"

set "from_1=%storage%\%app%"
set "to_1=%appdata%\%app%"

rd /s /q "%to_1%"

mklink /D "%to_1%" "%from_1%"

endlocal