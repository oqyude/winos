@echo off
setlocal

set "app=transmission"

set "from_1=%storage-programs%\Transmission\%computername%"
set "to_1=%localappdata%\%app%"

rd /s /q "%to_1%"

mklink /D "%to_1%" "%from_1%"

endlocal