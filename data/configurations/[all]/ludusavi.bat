@echo off
setlocal

set "app=ludusavi"

set "from_1=%storage%\%app%\cfg"
set "to_1=%appdata%\%app%"

rd /s /q "%to_1%"

mklink /D "%to_1%" "%from_1%"

endlocal