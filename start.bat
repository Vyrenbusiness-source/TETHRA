@echo off
REM TETHRA starten (Godot 4.7, Windows).
REM Startet die Main-Scene (Song-Browser) aus dem Projektordner.

setlocal
cd /d "%~dp0"

set "GODOT=Godot_v4.7-stable_win64.exe"

if not exist "%GODOT%" (
    echo [FEHLER] %GODOT% nicht gefunden im Projektordner.
    echo Lege die Godot-4.7-Executable neben diese start.bat.
    pause
    exit /b 1
)

echo Starte TETHRA...
start "" "%GODOT%" --path .

endlocal
