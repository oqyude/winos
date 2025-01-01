@echo off
setlocal

set "app=Sublime Text"

set "from_1=%storage-programs%\%app%\Config"
set "to_1=%AppData%\%app%"
set "from_exe_1=%storage-programs%\%app%\Patched\Windows\sublime_text.exe"
set "to_exe_1=%ProgramFiles%\%app%\sublime_text.exe"

rd /s /q "%to_1%"

copy /y "%from_exe_1%" "%to_exe_1%"
mklink /D "%to_1%" "%from_1%"

endlocal