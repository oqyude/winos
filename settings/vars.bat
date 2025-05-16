:: LOCAL ::

:: Package Managers
set "chocolatey=%~dp0chocolatey.ps1"
set "scoop=%~dp0scoop.ps1"
set "winget=%~dp0winget.ps1"
set "pin-list=%~dp0pin-list.bat"

:: Local Root
set "data=%root%\data"

:: Packages
set "packages=%data%\packages"
set "packages-installer=%packages%\install.bat"
set "packages-all-lists=%packages%\[all]"
set "packages-user-lists=%packages%\%computername%"
set "packages-user-lists-other=%packages-user-lists%\other.bat"

:: Configurations
set "configurations=%data%\configurations"
set "configurations-all=%configurations%\[all]"
set "configurations-user=%configurations%\%computername%"
:: Mounts
set "mounts=%data%\mounts"


:: GLOBAL ::
set "disk-label=S:"
set "user-name=oqyude"

:: Main Folder
set "games=%disk-label%\Games"
set "storage=%userprofile%\Storage"