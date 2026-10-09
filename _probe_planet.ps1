$fw = 'C:\Users\user\Desktop\ds harness\experiment'
Start-Process -FilePath "$fw\godot\Godot_v4.7.2-stable_win64_console.exe" -ArgumentList @('--path',('"{0}"' -f "$fw\gdgs_lab"),'res://planet_probe.tscn') -WindowStyle Hidden -RedirectStandardOutput "$fw\gdgs_lab\planet_probe.log" -RedirectStandardError "$fw\gdgs_lab\planet_probe.err"
Write-Output 'probe launched'
