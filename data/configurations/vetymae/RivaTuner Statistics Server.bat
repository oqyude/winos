@echo off
setlocal

set "app=RivaTuner Statistics Server"

set "from_1=%storage-programs%\%app%\Profiles"
set "to_1=%ProgramFiles(x86)%\%app%\Profiles"

rd /s /q "%to_1%"

mklink /D "%to_1%" "%from_1%"

endlocal