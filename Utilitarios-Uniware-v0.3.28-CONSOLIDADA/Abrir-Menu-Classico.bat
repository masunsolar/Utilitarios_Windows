@echo off
setlocal
title Utilitario Uniware - Menu Classico

fsutil dirty query %systemdrive% >nul 2>&1
if %errorLevel% NEQ 0 (
    powershell.exe -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Utilitarios_Uniware.PS1" -Action Menu
endlocal

