setlocal

set "init=%~dp0\..\settings\init.bat"
call %init%

for %%f in ("%apps-all%\*.bat") do (
    echo Running %%f - disconnect
    call "%%f" disconnect
)
for %%f in ("%apps-user%\*.bat") do (
    echo Running %%f - disconnect
    call "%%f" disconnect
)

endlocal