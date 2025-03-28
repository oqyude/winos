@echo off

:: .ssh
setlocal
set "from_1=%storage%\SSH\%computername%"
set "to_1=%USERPROFILE%\.ssh"
rd /s /q "%to_1%"
mklink /D "%to_1%" "%from_1%"
endlocal

:: Music
::setlocal
::set "from_1=%music-folder%"
::set "to_1=%USERPROFILE%\Music\My"
::rd /s /q "%to_1%"
::mklink /D "%to_1%" "%from_1%"
::endlocal

:: Gallery
::setlocal
::set "from_1=%gallery-folder%"
::set "to_1=%USERPROFILE%\Pictures\Gallery"
::rd /s /q "%to_1%"
::mklink /J "%to_1%" "%from_1%"
::endlocal

:: DaVinci Resolve Project Media
setlocal
set "from_1=%storage%\Davinci Resolve"
set "to_1=%USERPROFILE%\Videos\Davinci Resolve"
rd /s /q "%to_1%"
mklink /D "%to_1%" "%from_1%"
endlocal

:: Bash
setlocal
set "from_1=%storage%\User Folder\.bashrc"
set "to_1=%USERPROFILE%\.bashrc"
set "from_2=%storage%\User Folder\.inputrc"
set "to_2=%USERPROFILE%\.inputrc"
rd /s /q "%to_1%"
rd /s /q "%to_2%"
mklink "%to_1%" "%from_1%"
mklink "%to_2%" "%from_2%"
endlocal