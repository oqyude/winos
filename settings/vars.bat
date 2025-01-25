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
set "disk-label=D:"

:: Main Folder
set "structure=%disk-label%\Structure"
set "games=%disk-label%\Games"

:: Storage
set "storage=%structure%\Shared\Storage"
set "storage-programs=%storage%\Programs"
set "storage-games=%storage%\Games"
set "storage-settings=%storage%\Settings"
set "storage-daws=%storage%\DAWs"
set "storage-daws-plugins=%storage-daws%\Plugins"


:: User Folders
set "user-folder=%structure%\User"
set "music-folder=%user-folder%\Music"