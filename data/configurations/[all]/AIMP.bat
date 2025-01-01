@echo off
setlocal

set "app=AIMP"

set "from_1=%storage-programs%\%app%"
set "to_1=%appdata%\AIMP"

rd /s /q "%to_1%"

mklink /D "%to_1%" "%from_1%"

endlocal