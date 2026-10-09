$fw = 'C:\Users\user\Desktop\ds harness\experiment'
Start-Process -FilePath "$fw\godot\Godot_v4.7.2-stable_win64_console.exe" -ArgumentList @('--path',('"{0}"' -f "$fw\gdgs_lab"),'res://solar_combat.tscn','--','autotest','shots','demo') -WindowStyle Hidden -RedirectStandardOutput "$fw\gdgs_lab\game_shots.log" -RedirectStandardError "$fw\gdgs_lab\game_shots.err"
Write-Output 'game shots launched'
