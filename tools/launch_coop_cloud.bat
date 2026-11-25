@echo off
setlocal
cd /d "%~dp0.."

set "HOST=%~1"
set "PORT=%~2"
if "%HOST%"=="" (
    set /p "HOST=Enter server host/IP [127.0.0.1]: "
)
if "%HOST%"=="" set "HOST=127.0.0.1"
if "%PORT%"=="" set "PORT=27890"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev_launch.ps1" -Count 2 -AutoJoin -HostAddr "%HOST%" -Port %PORT%
pause
