@echo off
setlocal

set "app=AIMP"

set "from_1=%storage%\%app%"
set "to_1=%appdata%\%app%"

rd /S /Q "%to_1%"

mklink /D "%to_1%" "%from_1%"

endlocal