$fw = 'C:\Users\user\Desktop\ds harness\experiment'
Start-Process -FilePath "$fw\godot\Godot_v4.7.2-stable_win64_console.exe" -ArgumentList @('--path',('"{0}"' -f "$fw\gdgs_lab"),'res://whale_showcase.tscn') -WindowStyle Hidden -RedirectStandardOutput "$fw\gdgs_lab\whale_show.log" -RedirectStandardError "$fw\gdgs_lab\whale_show.err"
Write-Output 'whale showcase launched'
