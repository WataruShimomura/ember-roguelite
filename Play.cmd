@echo off
setlocal
cd /d "%~dp0"
if exist "tools\Godot_v4.6-stable_win64.exe" (
  start "EMBER" "tools\Godot_v4.6-stable_win64.exe" --path "%~dp0."
) else (
  echo Open project.godot with Godot 4.6 and press F6 or F5.
  echo Download: https://godotengine.org/download/archive/4.6-stable/
  pause
)
