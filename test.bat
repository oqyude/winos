@echo off

:: Init
call init.bat

for %%f in ("test\*.bat") do (
    echo Running %%f
    call "%%f"
)