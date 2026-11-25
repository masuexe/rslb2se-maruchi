@echo off
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev_launch.ps1" -Count 2 -AutoJoin -HostAddr 111.229.100.54 -Port 27890
pause
