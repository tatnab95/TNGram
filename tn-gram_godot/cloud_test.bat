@echo off
rem ---------------------------------------------------------------------------
rem  Проверка ОБЛАЧНОЙ связи (Supabase) — по-настоящему, через интернет.
rem  Нужен интернет. Проверка трогает только свои тестовые строки в облаке
rem  и убирает их за собой.
rem ---------------------------------------------------------------------------

set "GODOT_EXE=C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"

if not exist "%GODOT_EXE%" (
    where godot >nul 2>nul
    if errorlevel 1 (
        echo Godot not found. Open cloud_test.bat and set the correct GODOT_EXE path.
        pause
        exit /b 1
    )
    set "GODOT_EXE=godot"
)

rem Отдельный профиль: проверка не касается настоящих данных приложения
set "TNGRAM_PROFILE=smoke"

echo === Облако: два клиента через интернет ===
"%GODOT_EXE%" --headless --path "%~dp0." res://tests/CloudTest.tscn
set "CLOUD_OK=%ERRORLEVEL%"

echo.
echo === Облако: настоящее приложение и собеседник ===
"%GODOT_EXE%" --headless --path "%~dp0." res://tests/CloudAppTest.tscn
set "APP_OK=%ERRORLEVEL%"

del "%APPDATA%\Godot\app_userdata\TNGram\tngram_data_smoke.json" >nul 2>nul

echo.
echo Report files:
echo   %APPDATA%\Godot\app_userdata\TNGram\cloud_report.txt
echo   %APPDATA%\Godot\app_userdata\TNGram\cloud_app_report.txt
echo.

if "%CLOUD_OK%"=="0" if "%APP_OK%"=="0" (
    echo Cloud tests passed.
) else (
    echo Cloud tests failed, see the reports above.
)
pause
