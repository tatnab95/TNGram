@echo off
rem ---------------------------------------------------------------------------
rem  Второе окно TNGram со своим профилем (свои аккаунты и своя переписка).
rem  Нужно, чтобы проверить связь на одном компьютере: в одном окне вошли как
rem  админ, в этом — как админ2. Оба окна подключаются к серверу из relay.bat.
rem ---------------------------------------------------------------------------

set "GODOT_EXE=C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"

if not exist "%GODOT_EXE%" (
    where godot >nul 2>nul
    if errorlevel 1 (
        echo Godot not found. Open run_second.bat and set the correct GODOT_EXE path.
        pause
        exit /b 1
    )
    set "GODOT_EXE=godot"
)

set "TNGRAM_PROFILE=second"

"%GODOT_EXE%" --path "%~dp0."

if errorlevel 1 (
    echo.
    echo The app exited with an error. The text above may explain why.
    pause
)
