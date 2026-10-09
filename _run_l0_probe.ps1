# project root = directory of this script; Godot console exe from $env:GODOT or PATH
$proj = $PSScriptRoot
$exe = if ($env:GODOT) { $env:GODOT } else { 'Godot_v4.7.2-stable_win64_console.exe' }
Start-Process -FilePath $exe -ArgumentList @('--path',('"{0}"' -f $proj),'res://l0_stream_probe.tscn') -WindowStyle Hidden -RedirectStandardOutput "$proj\l0_probe.log" -RedirectStandardError "$proj\l0_probe.err"
Write-Output 'l0 probe launched'
