# project root = directory of this script; Godot console exe from $env:GODOT or PATH
$proj = $PSScriptRoot
$exe = if ($env:GODOT) { $env:GODOT } else { 'Godot_v4.7.2-stable_win64_console.exe' }
Start-Process -FilePath $exe -ArgumentList @('--path',('"{0}"' -f $proj),'res://solar_combat.tscn','--','autotest','shots','demo') -WindowStyle Hidden -RedirectStandardOutput "$proj\game_shots.log" -RedirectStandardError "$proj\game_shots.err"
Write-Output 'game shots launched'
