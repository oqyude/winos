@echo off

:: .ssh
setlocal
set "from_1=%storage%\SSH\%user-name%"
set "to_1=%USERPROFILE%\.ssh"
rd /q "%to_1%"
mklink /D "%to_1%" "%from_1%"
endlocal

:: Bash
setlocal
set "from_1=%storage%\User Folder\.bashrc"
set "to_1=%USERPROFILE%\.bashrc"
set "from_2=%storage%\User Folder\.inputrc"
set "to_2=%USERPROFILE%\.inputrc"
set "from_3=%storage%\User Folder\.gitconfig"
set "to_3=%USERPROFILE%\.gitconfig"
del /q "%to_1%"
del /q "%to_2%"
del /q "%to_3%"
mklink "%to_1%" "%from_1%"
mklink "%to_2%" "%from_2%"
mklink "%to_3%" "%from_3%"
endlocal

:: WSL
setlocal
set "from_1=%storage%\User Folder\.wslconfig"
set "to_1=%USERPROFILE%\.wslconfig"
del /q "%to_1%"
mklink "%to_1%" "%from_1%"
endlocal