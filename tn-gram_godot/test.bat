@echo off
rem ---------------------------------------------------------------------------
rem  Автопроверки TNGram, окно не нужно.
rem  1) интерфейс и данные (102 проверки), 2) связь (21 проверка).
rem  Внимание: проверка сбрасывает данные приложения и в конце оставляет
rem  чистый старт (только админ и админ2, без паролей и переписки).
rem ---------------------------------------------------------------------------

set "GODOT_EXE=C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"

if not exist "%GODOT_EXE%" (
    where godot >nul 2>nul
    if errorlevel 1 (
        echo Godot not found. Open test.bat and set the correct GODOT_EXE path.
        pause
        exit /b 1
    )
    set "GODOT_EXE=godot"
)

echo === Интерфейс и данные ===
"%GODOT_EXE%" --headless --path "%~dp0." res://tests/SmokeTest.tscn
set "SMOKE_OK=%ERRORLEVEL%"

echo.
echo === Связь: сервер и два клиента ===
"%GODOT_EXE%" --headless --path "%~dp0." res://tests/NetTest.tscn
set "NET_OK=%ERRORLEVEL%"

echo.
echo Report files:
echo   %APPDATA%\Godot\app_userdata\TNGram\smoke_report.txt
echo   %APPDATA%\Godot\app_userdata\TNGram\net_report.txt
echo.

if "%SMOKE_OK%"=="0" if "%NET_OK%"=="0" (
    echo All tests passed.
) else (
    echo Some tests failed, see the reports above.
)
pause
