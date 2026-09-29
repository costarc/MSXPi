@echo off
rem MSXPi Interface - openMSX + MSXPi installer for Windows
rem ---------------------------------------------------------------------------
rem MIT License - Copyright (c) 2015-2026 Ronivon Costa
rem ---------------------------------------------------------------------------
rem Double-click to run msxpi-windows-setup.ps1, which does all the work (see
rem the notes at its top). This file can also be downloaded on its own: without
rem the .ps1 next to it, it fetches the one on costarc/MSXPi master.
rem
rem Usage: msxpi-openmsx-install.bat [-Network] [-Branch name] [...]
rem        -Network also installs the TAP driver for MSX TCP/IP (asks for admin)
setlocal
set "PS1=%~dp0msxpi-windows-setup.ps1"
if exist "%PS1%" goto run
set "PS1=%TEMP%\msxpi-windows-setup.ps1"
echo Downloading msxpi-windows-setup.ps1 ...
powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = 'Tls12'; Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/costarc/MSXPi/master/software/Server/Setup/msxpi-windows-setup.ps1' -OutFile $env:PS1"
if errorlevel 1 (
    echo Download failed.
    pause
    exit /b 1
)
:run
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
