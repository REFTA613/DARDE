@echo off
title DCS-CAI Client Setup Launcher
color 0B

echo ====================================================
echo  LAUNCHER DCS-CAI CLIENT SETUP
echo ====================================================
echo.

:: 1. Check if the script is running with administrator privileges
net session >nul 2>&1
if %errorLevel% == 0 goto RunScript

:: If not administrator, execute this block
echo [WARNING] Administrator privileges required.
echo Please confirm the Windows (UAC) prompt that will appear...

:: Relaunch itself requesting privilege elevation
powershell -Command "Start-Process -FilePath '%~dpnx0' -Verb RunAs"
exit /B


:RunScript
:: 2. Ensure the working directory is that of the .bat file
cd /d "%~dp0"

echo Administrator privileges obtained. Starting PowerShell script...
echo.

:: 3. Launch the PowerShell script to set up the DCS-CAI Client
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "setup_cai_client_win.ps1"

echo.
pause
