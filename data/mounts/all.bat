@echo off

:: .ssh
setlocal
set "from_1=%storage%\SSH\%user-name%"
set "to_1=%USERPROFILE%\.ssh"
rd /q "%to_1%"
mklink /D "%to_1%" "%from_1%"
endlocal

rem :: Music
rem setlocal
rem set "from_1=%music-folder%"
rem set "to_1=%USERPROFILE%\Music\My"
rem rd /s /q "%to_1%"
rem mklink /D "%to_1%" "%from_1%"
rem endlocal

rem :: Gallery
rem setlocal
rem set "from_1=%gallery-folder%"
rem set "to_1=%USERPROFILE%\Pictures\Gallery"
rem rd /s /q "%to_1%"
rem mklink /J "%to_1%" "%from_1%"
rem endlocal

rem :: DaVinci Resolve Project Media
rem setlocal
rem set "from_1=%storage%\Davinci Resolve"
rem set "to_1=%USERPROFILE%\Videos\Davinci Resolve"
rem rd /s /q "%to_1%"
rem mklink /D "%to_1%" "%from_1%"
rem endlocal

:: Bash
setlocal
set "from_1=%storage%\User Folder\.bashrc"
set "to_1=%USERPROFILE%\.bashrc"
set "from_2=%storage%\User Folder\.inputrc"
set "to_2=%USERPROFILE%\.inputrc"
del /q "%to_1%"
del /q "%to_2%"
mklink "%to_1%" "%from_1%"
mklink "%to_2%" "%from_2%"
endlocal