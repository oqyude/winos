@echo off
setlocal

set "app=Nekoray"

set "from_1=%storage%\%app%\%computername%\config"
set "to_1=%localappdata%\Microsoft\WinGet\Packages\MatsuriDayo.NekoRay_Microsoft.Winget.Source_8wekyb3d8bbwe\nekoray\config"

rd /q "%to_1%"

mklink /D "%to_1%" "%from_1%"
endlocal