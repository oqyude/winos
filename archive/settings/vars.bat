:: LOCAL ::

:: Package Managers
set "winget=%root%\winget.ps1"

:: Local Root
set "data=%root%\data"

:: Packages
set "packages=%data%\packages"
set "packages-installer=%packages%\install.bat"
set "packages-all-lists=%packages%\[all]"
set "packages-user-lists=%packages%\%computername%"
set "packages-user-lists-other=%packages-user-lists%\other.bat"

:: Apps
set "apps=%data%\apps"
set "apps-all=%apps%\all.csv"
set "apps-legacy=%apps%\legacy"
set "apps-user=%apps%\%computername%"
:: Mounts
set "mounts=%data%\mounts"


:: GLOBAL ::
set "disk-label=S:"
set "user-name=oqyude"

:: Main Folder
set "games=%disk-label%\Games"
set "storage=%userprofile%\Storage"
set "storage-games=N:\Games\.storage"