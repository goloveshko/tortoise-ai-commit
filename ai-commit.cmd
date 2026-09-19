@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai-commit.ps1" %*

echo %cmdcmdline% | find /i "%~0" >nul && pause
