@echo off
setlocal
rem Godot console executable: take %GODOT% if set, else the one on PATH
set "GODOT_EXE=%GODOT%"
if "%GODOT_EXE%"=="" set "GODOT_EXE=Godot_v4.7.2-stable_win64_console.exe"
rem project root = directory of this script
set "PROJ=%~dp0"
if "%PROJ:~-1%"=="\" set "PROJ=%PROJ:~0,-1%"
"%GODOT_EXE%" --path "%PROJ%" res://sym_tuner.tscn > "%PROJ%\sym_tuner.log" 2>&1
