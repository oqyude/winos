@echo off
setlocal

set "app=64Gram Desktop"

set "from_1=%storage-programs%\%app%\%device_1%"
set "to_1=%appdata%\%app%\tdata"

rd /s /q "%to_1%"

mklink /D "%to_1%" "%from_1%"

endlocal