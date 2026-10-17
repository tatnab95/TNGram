@echo off
setlocal enabledelayedexpansion
rem ---------------------------------------------------------------------------
rem  TNGram: одним двойным кликом — сервер-передаточник (в отдельном окне)
rem  и приложение. Сервер слушает все интерфейсы (0.0.0.0), порт 7777.
rem  Адрес для друзей печатается ниже — впиши его в «Настройки → Связь».
rem  Только посмотреть адрес, ничего не запуская:  start.bat info
rem ---------------------------------------------------------------------------

set "GODOT_EXE=C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"

if not exist "%GODOT_EXE%" (
    where godot >nul 2>nul
    if errorlevel 1 (
        echo.
        echo Godot not found. Open start.bat and set the correct GODOT_EXE path.
        echo Looked for: "%GODOT_EXE%"
        echo.
        pause
        exit /b 1
    )
    set "GODOT_EXE=godot"
)

rem --- адрес этого компьютера: сначала Tailscale, иначе локальная сеть ---
set "TS_EXE="
where tailscale >nul 2>nul
if not errorlevel 1 set "TS_EXE=tailscale"
if not defined TS_EXE if exist "%ProgramFiles%\Tailscale\tailscale.exe" set "TS_EXE=%ProgramFiles%\Tailscale\tailscale.exe"

set "TAILSCALE_IP="
if defined TS_EXE (
    for /f "delims=" %%i in ('"%TS_EXE%" ip -4 2^>nul') do if not defined TAILSCALE_IP set "TAILSCALE_IP=%%i"
)

set "LOCAL_IP="
for /f "delims=" %%i in ('powershell -NoProfile -Command "(Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null } | Select-Object -First 1).IPv4Address.IPAddress" 2^>nul') do if not defined LOCAL_IP set "LOCAL_IP=%%i"

if defined TAILSCALE_IP (
    set "SHOW_IP=!TAILSCALE_IP!"
    set "IP_KIND=Tailscale network"
) else (
    set "SHOW_IP=!LOCAL_IP!"
    set "IP_KIND=home network, Wi-Fi or router"
)

echo.
echo   TNGram - relay server and app
echo   ===============================================================
if defined SHOW_IP (
    echo   Friends connect to:  ws://!SHOW_IP!:7777   - !IP_KIND!
) else (
    echo   Could not detect this computer address. Find it by hand:
    echo   open a console, run  ipconfig  and take the IPv4 address.
)
echo   On this computer:    ws://127.0.0.1:7777
echo   ===============================================================

rem --- файрвол: правило для входящего порта 7777 ---
set "FW_NAME=TNGram relay 7777"
netsh advfirewall firewall show rule name="%FW_NAME%" >nul 2>nul
if errorlevel 1 (
    echo.
    echo   WARNING: Windows Firewall may be blocking incoming port 7777.
    echo            Friends will not connect until it is open.
    echo            Run  firewall.bat  - it asks for administrator rights.
    echo            Or run this once in an administrator console:
    echo              netsh advfirewall firewall add rule name="%FW_NAME%" dir=in action=allow protocol=TCP localport=7777
) else (
    echo.
    echo   Firewall: rule for port 7777 is present.
)

if /i "%~1"=="info" (
    echo.
    exit /b 0
)

echo.
echo   Starting relay server in a separate window...
start "TNGram relay" "%~dp0relay.bat"

echo   Waiting 2 seconds, then starting the app...
ping -n 3 127.0.0.1 >nul 2>nul

echo.
"%GODOT_EXE%" --path "%~dp0."

if errorlevel 1 (
    echo.
    echo The app exited with an error. The text above may explain why.
    pause
)

endlocal
