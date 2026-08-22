@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Install-FinancialAdvisorFilter.ps1"
endlocal
