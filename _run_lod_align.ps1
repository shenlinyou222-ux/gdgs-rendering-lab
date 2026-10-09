param([string]$Phi = "0", [string]$Scene = "res://lod_align_probe.tscn", [string]$Align = "", [string]$Log = "lod_align")
$fw = 'C:\Users\user\Desktop\ds harness\experiment'
$exe = "$fw\godot\Godot_v4.7.2-stable_win64_console.exe"
$proj = "$fw\gdgs_lab"
$tail = "--phi=$Phi"
if ($Align -ne "") { $tail = "--align=$Align" }
$p = Start-Process -FilePath $exe -ArgumentList "--path",$proj,$Scene,'--',$tail -WindowStyle Hidden -RedirectStandardOutput "$fw\gdgs_lab\$Log.log" -RedirectStandardError "$fw\gdgs_lab\$Log.err" -PassThru -Wait
Write-Output ("exit=" + $p.ExitCode)
