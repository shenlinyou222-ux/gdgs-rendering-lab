param([string]$Phi = "0", [string]$Scene = "res://lod_align_probe.tscn", [string]$Align = "", [string]$Log = "lod_align")
# project root = directory of this script; Godot console exe from $env:GODOT or PATH
$proj = $PSScriptRoot
$exe = if ($env:GODOT) { $env:GODOT } else { 'Godot_v4.7.2-stable_win64_console.exe' }
$tail = "--phi=$Phi"
if ($Align -ne "") { $tail = "--align=$Align" }
$p = Start-Process -FilePath $exe -ArgumentList "--path",$proj,$Scene,'--',$tail -WindowStyle Hidden -RedirectStandardOutput "$proj\$Log.log" -RedirectStandardError "$proj\$Log.err" -PassThru -Wait
Write-Output ("exit=" + $p.ExitCode)
