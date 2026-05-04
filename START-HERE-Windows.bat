@echo off
setlocal
cd /d "%~dp0"
echo Whispergate Windows setup
echo.
echo This opens an Administrator PowerShell window and runs the guided setup.
echo Approve the Windows prompt when it appears.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\launch-windows-setup.ps1"
if errorlevel 1 (
  echo.
  echo Could not open Administrator PowerShell.
  echo Open PowerShell as Administrator, go to this folder, then run:
  echo scripts\setup-windows-beginner.ps1
  echo.
  pause
  exit /b 1
)
exit /b 0
