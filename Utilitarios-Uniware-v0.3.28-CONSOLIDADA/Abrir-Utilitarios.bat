@echo off
setlocal
title Utilitario Uniware - Interface Responsiva v0.3.29

fsutil dirty query %systemdrive% >nul 2>&1
if %errorLevel% NEQ 0 (
    echo Solicitando privilegios de Administrador...
    powershell.exe -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
if not exist "%~dp0Utilitarios_Uniware_GUI.ps1" (
    echo [ERRO] Utilitarios_Uniware_GUI.ps1 nao foi encontrado.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Utilitarios_Uniware_GUI.ps1"
endlocal

