@echo off
setlocal

set "app=glzr"

set "from_1=%storage-programs%\%app%"
set "to_1=%USERPROFILE%\.%app%"

rd /s /q "%to_1%"

mklink /D "%to_1%" "%from_1%"

endlocal