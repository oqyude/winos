setlocal

set "init=%~dp0\..\settings\init.bat"
call %init%

for %%f in ("%legacy%\*.bat") do (
    echo Running %%f - reconnect
    call "%%f"
)
for %%f in ("%legacy%\*.bat") do (
    echo Running %%f - reconnect
    call "%%f"
)

endlocal