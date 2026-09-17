@echo off
:: Double-click this file. It will ask for admin permission (click Yes),
:: then run the inventory collector automatically. No other steps needed.

:: --- Self-elevate to Administrator if not already ---
net session >nul 2>&1
if %errorLevel% == 0 goto :run

echo Requesting administrator permission...
powershell -Command "Start-Process '%~f0' -Verb RunAs"
exit /b

:run
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Collect-Inventory.ps1"
echo.
echo Done. Press any key to close.
pause >nul
