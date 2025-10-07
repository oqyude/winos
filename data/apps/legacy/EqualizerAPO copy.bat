@echo off
setlocal

set "app=EqualizerAPO"

set "from_1=%storage%\%App%" && set "to_1=%ProgramFiles%\%App%" && set "FabFilter Pro-Q 3=%ProgramFiles%\VSTPlugins\FabFilter\FabFilter Pro-Q 3.dll"

for /f "delims=" %%i in ('dir /aL /b %To%\config') do del "%%i" && del /q "%To%\config\*" && del /q "%To%\VSTPlugins\FabFilter Pro-Q 3.dll"

reg add "HKEY_LOCAL_MACHINE\SOFTWARE\EqualizerAPO" /v "ConfigPath" /t REG_SZ /d "%storage%\%App%" /f && mklink "%To%\VSTPlugins\FabFilter Pro-Q 3.dll" "%FabFilter Pro-Q 3%"

endlocal
