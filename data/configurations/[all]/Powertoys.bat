@echo off
setlocal

set "app=Powertoys"

set "from_1=%storage-programs%\%app%\%computername%"
set "to_1=%localappdata%\Microsoft\PowerToys"

rd /s /q "%to_1%"

mklink /D "%to_1%" "%from_1%"

endlocal