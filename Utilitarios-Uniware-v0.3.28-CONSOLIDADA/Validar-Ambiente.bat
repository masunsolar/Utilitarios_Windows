@echo off
setlocal
title Validacao do Ambiente Uniware v0.3.28
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Validar-Ambiente.ps1"
endlocal
