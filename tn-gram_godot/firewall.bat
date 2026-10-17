@echo off
rem ---------------------------------------------------------------------------
rem  Открывает входящий порт 7777/TCP в файрволе Windows — чтобы друзья извне
rem  могли подключиться к серверу-передаточнику. Запускать двойным кликом:
rem  скрипт сам попросит права администратора.
rem ---------------------------------------------------------------------------

set "FW_NAME=TNGram relay 7777"

rem Проверка прав: net session доступен только администратору.
net session >nul 2>nul
if errorlevel 1 (
    echo Asking for administrator rights...
    powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
    exit /b
)

echo Opening incoming TCP port 7777 for all networks...
netsh advfirewall firewall delete rule name="%FW_NAME%" >nul 2>nul
netsh advfirewall firewall add rule name="%FW_NAME%" dir=in action=allow protocol=TCP localport=7777
if errorlevel 1 (
    echo.
    echo Could not add the rule. The text above may explain why.
) else (
    echo.
    echo Done. Port 7777 is open for incoming connections.
    echo Run start.bat again - the firewall line should now say the rule is present.
)
echo.
pause
