@echo off
setlocal

set "app=EqualizerAPO"

set "from_1=%storage%\%app%" && set "to_1=%ProgramFiles%\%app%" && set "FabFilter_Pro-Q_3=%ProgramFiles%\VSTPlugins\FabFilter\FabFilter Pro-Q 3.dll"

for /f "delims=" %%i in ('dir /aL /b %to_1%\config') do del "%%i" && del /q "%to_1%\config\*" && del /q "%to_1%\VSTPlugins\FabFilter Pro-Q 3.dll"

reg add "HKEY_LOCAL_MACHINE\SOFTWARE\EqualizerAPO" /v "ConfigPath" /t REG_SZ /d "%storage%\%app%" /f && mklink "%to_1%\VSTPlugins\FabFilter Pro-Q 3.dll" "%FabFilter_Pro-Q_3%"

endlocal
