extends SceneTree
func _init() -> void:
	var dir := "C:/Users/user/Desktop/ds harness/experiment/gdgs_lab/probe_png/"
	var names := ["sunprobe_off_-30.0.png","sunprobe_off_-20.0.png","sunprobe_off_-15.0.png","sunprobe_off_-10.0.png","sunprobe_off_-05.0.png","sunprobe_off_+00.0.png","sunprobe_off_+05.0.png","sunprobe_off_+10.0.png","sunprobe_off_+30.0.png"]
	var chars := " .:-=+*#%@"
	for nm in names:
		var img := Image.load_from_file(dir + nm)
		if img == null:
			print(nm, " LOAD FAIL")
			continue
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		var w := img.get_width()
		var h := img.get_height()
		var gw := 48
		var gh := 27
		print("==== " + nm + " " + str(w) + "x" + str(h) + " ====")
		for gy in gh:
			var line := ""
			for gx in gw:
				var sx := int((gx + 0.5) * w / gw)
				var sy := int((gy + 0.5) * h / gh)
				var c := img.get_pixel(sx, sy)
				var lum := (c.r + c.g + c.b) / 3.0
				line += chars[clampi(int(lum * 9.999), 0, 9)]
			print(line)
	quit()
