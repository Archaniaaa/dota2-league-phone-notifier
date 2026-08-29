@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_PATH=%SCRIPT_DIR%DotaMatchNotifier.ps1"

if not exist "%SCRIPT_PATH%" (
    echo ERROR: DotaMatchNotifier.ps1 was not found beside this launcher.
    pause
    endlocal & exit /b 2
)

where pwsh.exe >nul 2>&1
if errorlevel 1 goto :windows_powershell

pwsh.exe -NoLogo -NoProfile -File "%SCRIPT_PATH%" %*
set "EXIT_CODE=%ERRORLEVEL%"
goto :finished

:windows_powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" %*
set "EXIT_CODE=%ERRORLEVEL%"

:finished

if not "%EXIT_CODE%"=="0" (
    echo.
    echo Dota Match Notifier exited with code %EXIT_CODE%.
    pause
)

endlocal & exit /b %EXIT_CODE%
