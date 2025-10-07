@echo off

cd /d "%~dp0"
set "root=%~dp0..\"

set "vars=%root%\settings\vars.bat"
call "%vars%"