@echo off
setlocal
title Build Carpet Cleaner APK
pushd "%~dp0"
if errorlevel 1 exit /b 1
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\build_android.ps1" %*
set "BUILD_RESULT=%ERRORLEVEL%"
popd
echo.
if not "%BUILD_RESULT%"=="0" echo Build did not finish. Read the error above and build\android-build-launcher.log.
pause
exit /b %BUILD_RESULT%
