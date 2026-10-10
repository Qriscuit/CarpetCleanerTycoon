@echo off
setlocal
title Collect Carpet Cleaner Android Crash Logs
pushd "%~dp0"
if errorlevel 1 exit /b 1
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\collect_android_crash_logs.ps1" %*
set "COLLECTION_RESULT=%ERRORLEVEL%"
popd
echo.
pause
exit /b %COLLECTION_RESULT%
