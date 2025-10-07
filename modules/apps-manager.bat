@echo off
:: ==========================================
:: Проверка прав администратора
:: ==========================================
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo Требуются права администратора. Перезапуск...
    powershell -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    exit /b
)

:: ==========================================
:: Инициализация
:: ==========================================
setlocal EnableDelayedExpansion
set "init=%~dp0\..\settings\init.bat"
call "%init%"

set "config=%csv%"

:: ==========================================
:: Аргумент действия
:: ==========================================
set "action=%1"
if "%action%"=="" set "action=reconnect"

:: ==========================================
:: Обработка CSV
:: ==========================================
for /f "skip=1 tokens=1-8 delims=," %%A in (%config%) do (
    set "App=%%A"
    set "From=%%B"
    set "To=%%C"
    set "Type=%%D"
    set "Enabled=%%E"
    set "ExtraVariables=%%F"
    set "ExtraConnect=%%G"
    set "ExtraDisconnect=%%H"

    if "!Enabled!"=="1" (
        :: Разворачиваем стандартные переменные окружения
        call set "From=!From!"
        call set "To=!To!"
        if not "!ExtraConnect!"=="" call set "ExtraConnect=!ExtraConnect!"
        if not "!ExtraDisconnect!"=="" call set "ExtraDisconnect=!ExtraDisconnect!"

        :: Выполняем Extra-Variables как команду
        if not "!ExtraVariables!"=="" (
            call !ExtraVariables!
        )

        echo ==============================
        echo Processing !App! with action %action% (Type=!Type!)

        if /I "!Type!"=="isolate" (
            :: Для isolate исполняем только extra команды
            if /I "%action%"=="disconnect" if not "!ExtraDisconnect!"=="" call !ExtraDisconnect!
            if /I "%action%"=="connect" if not "!ExtraConnect!"=="" call !ExtraConnect!
            if /I "%action%"=="reconnect" (
                if not "!ExtraDisconnect!"=="" call !ExtraDisconnect!
                if not "!ExtraConnect!"=="" call !ExtraConnect!
            )
        ) else (
            :: default — обычное поведение
            if /I "%action%"=="disconnect" call :disconnect
            if /I "%action%"=="connect" call :connect
            if /I "%action%"=="reconnect" (
                call :disconnect
                call :connect
            )
        )
    )
)

:: ==========================================
:: Завершение
:: ==========================================
:end
endlocal
exit /b

:: ==========================================
:: Функции
:: ==========================================
:disconnect
echo Removing "!To!"...
rd /S /Q "!To!" 2>nul
if not "!ExtraDisconnect!"=="" call !ExtraDisconnect!
goto :eof

:connect
echo Creating symlink "!To!" -> "!From!"...
mklink /D "!To!" "!From!"
if not "!ExtraConnect!"=="" call !ExtraConnect!
goto :eof
