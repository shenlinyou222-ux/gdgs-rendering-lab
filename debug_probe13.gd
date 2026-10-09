extends Node3D
var game: Node3D
var t := 0.0
var opened := false
var maxdt := 0.0
var last_ms := 0.0

func _ready() -> void:
	process_priority = 100
	game = (load("res://solar_combat.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	game.autopilot = false
	last_ms = float(Time.get_ticks_msec())
	print("PROBE13 start")

func _process(dt: float) -> void:
	var now := float(Time.get_ticks_msec())
	var fd := now - last_ms
	last_ms = now
	t += dt
	if t >= 1.5 and fd > maxdt:
		maxdt = fd
	if not opened and t >= 2.0:
		opened = true
		var ms0 := float(Time.get_ticks_msec())
		game._open_gate()
		print("OPEN-CALL took %.1f ms" % (float(Time.get_ticks_msec()) - ms0))
	if t >= 5.5:
		print("PROBE13 max_frame_gap=%d ms (1.5s-5.5s 窗口)" % int(maxdt))
		print("PROBE13-DONE")
		get_tree().quit()
