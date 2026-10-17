@echo off
rem ---------------------------------------------------------------------------
rem  Запуск приложения TNGram (проект Godot 4.7).
rem  Если Godot установлен в другом месте — поправь путь GODOT_EXE ниже.
rem  Окно консоли остаётся открытым, пока работает приложение: если что-то
rem  пойдёт не так, здесь будет видно сообщение об ошибке.
rem ---------------------------------------------------------------------------

set "GODOT_EXE=C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"

if not exist "%GODOT_EXE%" (
    where godot >nul 2>nul
    if errorlevel 1 (
        echo.
        echo Godot not found. Open run.bat and set the correct GODOT_EXE path.
        echo Looked for: %GODOT_EXE%
        echo.
        pause
        exit /b 1
    )
    set "GODOT_EXE=godot"
)

"%GODOT_EXE%" --path "%~dp0."

if errorlevel 1 (
    echo.
    echo The app exited with an error. The text above may explain why.
    pause
)
