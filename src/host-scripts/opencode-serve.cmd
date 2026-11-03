@echo off
rem opencode-serve.cmd -- the Windows face of the launcher.
rem
rem Thin on purpose: it finds bash and hands everything over to
rem opencode-serve.sh, which holds the whole logic. A second copy of the
rem logic in a .cmd file is a second copy that rots.
rem
rem   opencode-serve.cmd            start the server (foreground)
rem   opencode-serve.cmd stop       ask the running server to stop
rem   opencode-serve.cmd status     say whether the server runs
rem
rem The Git Bash is looked up FIRST, and the PATH second: on Windows
rem "where bash" finds the WSL bash often enough, and the WSL bash cannot
rem see the Windows filesystem the way the Git Bash does.

setlocal
set "SCRIPT_DIR=%~dp0"

set "BASH="
if exist "%ProgramFiles%\Git\bin\bash.exe" set "BASH=%ProgramFiles%\Git\bin\bash.exe"
if not defined BASH if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "BASH=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not defined BASH if exist "%LOCALAPPDATA%\Programs\Git\bin\bash.exe" set "BASH=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
if not defined BASH (
    for /f "delims=" %%P in ('where bash 2^>nul') do (
        if not defined BASH set "BASH=%%P"
    )
)
if not defined BASH (
    echo opencode-serve: bash is not found. 1>&2
    echo opencode-serve: install Git for Windows, or run opencode-serve.sh from a bash shell. 1>&2
    exit /b 1
)

"%BASH%" "%SCRIPT_DIR%opencode-serve.sh" %*
exit /b %ERRORLEVEL%
