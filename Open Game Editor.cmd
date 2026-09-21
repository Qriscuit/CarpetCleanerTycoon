@echo off
setlocal
if not exist "%~dp0tools\godot\Godot_v4.7.2-stable_win64.exe" (
  echo The bundled standard Godot 4.7.2 editor is missing from tools\godot.
  pause
  exit /b 1
)
start "" "%~dp0tools\godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0CarpetToy" --editor res://scenes/production/floating_home.tscn
