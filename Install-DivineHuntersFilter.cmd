@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Install-DivineHuntersFilter.ps1"
endlocal
