# project root = directory of this script; Godot console exe from $env:GODOT or PATH
$proj = $PSScriptRoot
$exe = if ($env:GODOT) { $env:GODOT } else { 'Godot_v4.7.2-stable_win64_console.exe' }
Start-Process -FilePath $exe -ArgumentList @('--path',('"{0}"' -f $proj),'res://cell_probe.tscn') -WindowStyle Hidden -RedirectStandardOutput "$proj\probe_run.log" -RedirectStandardError "$proj\probe_run.err"
Write-Output 'godot launched'
