@echo off
setlocal

:Choco
choco feature enable allowGlobalConfirmation
choco install "%packages-user-lists%\choco.config" -y

:Winget
winget import -i "%packages-user-lists%\msstore.json" --accept-package-agreements --accept-source-agreements
winget import -i "%packages-user-lists%\winget.json" --accept-package-agreements --accept-source-agreements

:Pin-lists
call %pin-list%
call %packages-user-lists-other%

for %%i in (%winget-pin-list%) do (
    echo Pinning %%i...
    cmd /c winget pin add --id "%%i"
)
for %%i in (%choco-pin-list%) do (
    echo Pinning %%i...
    cmd /c choco pin add --name="'%%i'"
)

for %%i in (%winget-other-list%) do (
    echo Installing %%i...
    cmd /c winget install "'%%i'"
)
for %%i in (%choco-other-list%) do (
    echo Installing %%i...
    cmd /c choco install "'%%i'"
)

endlocal