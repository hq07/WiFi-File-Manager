@echo off
chcp 65001 >nul
title WiFi File Manager

cd /d "%~dp0"

set "UV=%USERPROFILE%\.local\bin\uv.exe"

if not exist "%UV%" (
    echo Installing uv...
    powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
    if not exist "%UV%" (
        echo.
        echo Install failed. Download Python from https://www.python.org/downloads/
        pause
        exit /b 1
    )
)

REM Use separate venv for Windows to avoid conflict with Mac/Linux venv
set "UV_PROJECT_ENVIRONMENT=.venv-win"

echo.
echo ========================================
echo   WiFi File Manager
echo   http://localhost:7777
echo   Ctrl+C to stop / Close window to exit
echo ========================================
echo.

"%UV%" run python -m server.main
pause
