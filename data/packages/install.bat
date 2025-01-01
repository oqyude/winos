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

for %%i in (%winget-pin-list%) do (
    echo Pinning %%i...
    cmd /c winget pin add --id "%%i"
)
for %%i in (%choco-pin-list%) do (
    echo Pinning %%i...
    cmd /c choco pin add --name="'%%i'"
)

endlocal