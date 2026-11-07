@echo off
setlocal
set "FLAG=%USERPROFILE%\.local\state\oc-serve\stop"
set "LOG=%USERPROFILE%\.local\state\oc-serve\serve.log"
> "%FLAG%" echo stop
echo Stop requested, waiting for the server to exit...
for /l %%i in (1,1,20) do (
  >nul 2>&1 netstat -an | find /i ":4096" | find /i "LISTENING" || goto done
  >nul 2>&1 timeout /t 1
)
echo Still listening on port 4096 - see "%LOG%"
exit /b 1
:done
echo Server stopped.
exit /b 0
