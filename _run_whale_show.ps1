# project root = directory of this script; Godot console exe from $env:GODOT or PATH
$proj = $PSScriptRoot
$exe = if ($env:GODOT) { $env:GODOT } else { 'Godot_v4.7.2-stable_win64_console.exe' }
Start-Process -FilePath $exe -ArgumentList @('--path',('"{0}"' -f $proj),'res://whale_showcase.tscn') -WindowStyle Hidden -RedirectStandardOutput "$proj\whale_show.log" -RedirectStandardError "$proj\whale_show.err"
Write-Output 'whale showcase launched'
