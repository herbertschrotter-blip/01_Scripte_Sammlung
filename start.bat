@echo off
setlocal

REM Optional: saubere UTF-8 Anzeige in CMD
chcp 65001 >nul

REM PowerShell 7 bevorzugen (wie in VS Code)
where pwsh >nul 2>&1
if %errorlevel%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1"
)

pause
endlocal
