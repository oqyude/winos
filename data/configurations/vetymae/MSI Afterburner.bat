@echo off
setlocal

set "app=MSI Afterburner"

set "from_1=%storage-programs%\%app%\Profiles"
set "to_1=%ProgramFiles(x86)%\%app%\Profiles"

set "from_2=%storage-programs%\%app%\MSIAfterburner.cfg"
set "to_2=%ProgramFiles(x86)%\%app%\MSIAfterburner.cfg"

rd /s /q "%to_1%"
del /s /q "%to_2%"

mklink /D "%to_1%" "%from_1%"
mklink "%to_2%" "%from_2%"

endlocal