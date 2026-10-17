@echo off
rem ---------------------------------------------------------------------------
rem  Автопроверки TNGram, окно не нужно.
rem  1) интерфейс и данные (114 проверок), 2) связь в своей сети (21 проверка).
rem  Проверки идут в отдельном профиле (tngram_data_smoke.json), поэтому твои
rem  аккаунты и переписка не трогаются.
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

rem Отдельный профиль: проверка не касается настоящих данных приложения
set "TNGRAM_PROFILE=smoke"

echo === Интерфейс и данные ===
"%GODOT_EXE%" --headless --path "%~dp0." res://tests/SmokeTest.tscn
set "SMOKE_OK=%ERRORLEVEL%"

echo.
echo === Связь: сервер и два клиента ===
"%GODOT_EXE%" --headless --path "%~dp0." res://tests/NetTest.tscn
set "NET_OK=%ERRORLEVEL%"

rem Убираем временный профиль проверки
del "%APPDATA%\Godot\app_userdata\TNGram\tngram_data_smoke.json" >nul 2>nul

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
