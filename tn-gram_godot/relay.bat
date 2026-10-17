@echo off
rem ---------------------------------------------------------------------------
rem  Сервер-передаточник TNGram.
rem  Держит сообщение, пока получатель его не заберёт, и сразу удаляет.
rem  Держи это окно открытым, пока общаешься. Для друзей в той же сети —
rem  подключайся к адресу этого компьютера (номер порта снизу), а не к localhost.
rem ---------------------------------------------------------------------------

set "GODOT_EXE=C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"

if not exist "%GODOT_EXE%" (
    where godot >nul 2>nul
    if errorlevel 1 (
        echo Godot not found. Open relay.bat and set the correct GODOT_EXE path.
        pause
        exit /b 1
    )
    set "GODOT_EXE=godot"
)

echo Starting relay server on port 7777, press Ctrl+C to stop.
echo.

"%GODOT_EXE%" --headless --path "%~dp0." res://relay/RelayServer.tscn

if errorlevel 1 (
    echo.
    echo The relay exited with an error. The text above may explain why.
    pause
)
