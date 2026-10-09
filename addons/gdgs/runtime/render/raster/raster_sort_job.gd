@tool
extends RefCounted

## WorkerThreadPool job wrapper with a double-buffered order handoff for one
## splat node. The sort runs off the main thread on an immutable position
## snapshot and writes the back buffer; the main thread keeps rendering from the
## front buffer until the task completes, then swaps. This is what lets the
## per-frame sort lag the camera by a frame or two without stalling rendering.
##
## The worker produces the finished R32F order-texture bytes, not just indices:
## the int→float conversion and the byte packing both happen here so the main
## thread's entire share of a completed sort is Image.set_data + texture update.

const Sorter := preload("res://addons/gdgs/runtime/render/raster/raster_sorter.gd")

const SETTING_FAR_SORT_FRACTION := "gdgs/opt/far_sort_fraction"
const SETTING_SORT_DEBUG := "gdgs/opt/sort_debug"

var _xyz: PackedVector3Array = PackedVector3Array()
var _texel_count := -1
var _order_buffers: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
var _byte_buffers := [PackedByteArray(), PackedByteArray()]
var _front := 0
var _task_id := -1
var _pending_dir := Vector3.ZERO
var _has_front := false
var _force_full := false
var _last_sort_ms := 0.0

func set_positions(xyz: PackedVector3Array) -> void:
	_xyz = xyz

func set_texel_count(texel_count: int) -> void:
	_texel_count = texel_count

func is_running() -> bool:
	return _task_id != -1

func last_sort_ms() -> float:
	return _last_sort_ms

func front_bytes() -> PackedByteArray:
	return _byte_buffers[_front]

## Start a sort into the back buffer for the given local-space view direction.
## `force_full` (camera teleports / first sort) disables C1 far-reuse for this
## kick: the far block must never freeze a stale order across a large camera
## swing. No-op if a task is already in flight. Returns true if a task started.
func kick(view_dir_local: Vector3, force_full: bool = false) -> bool:
	if _task_id != -1:
		return false
	_pending_dir = view_dir_local
	_force_full = force_full
	_task_id = WorkerThreadPool.add_task(Callable(self, "_run"), false, "gdgs raster sort")
	return true

func _run() -> void:
	var t0 := Time.get_ticks_usec()
	var back := 1 - _front
	var prev: PackedFloat32Array = _order_buffers[_front] if _has_front else PackedFloat32Array()
	var fraction := 0.0 if _force_full else float(ProjectSettings.get_setting(SETTING_FAR_SORT_FRACTION, 0.0))
	Sorter.sort_into_aware(_xyz, _pending_dir, prev, fraction, _order_buffers[back], _texel_count)
	_byte_buffers[back] = _order_buffers[back].to_byte_array()
	_last_sort_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	if bool(ProjectSettings.get_setting(SETTING_SORT_DEBUG, false)):
		var n := _xyz.size()
		var far := 0
		if fraction > 0.0 and n > 0 and prev.size() >= n:
			var k := maxi(int(float(n) * clampf(fraction, 0.0, 1.0)), 1)
			var boundary := clampi(int(prev[mini(k - 1, n - 1)] + 0.5), 0, n - 1)
			var dx := _pending_dir.x; var dy := _pending_dir.y; var dz := _pending_dir.z
			var thresh := _xyz[boundary].x * dx + _xyz[boundary].y * dy + _xyz[boundary].z * dz
			for i in range(n):
				var q := _xyz[i]
				if q.x * dx + q.y * dy + q.z * dz >= thresh:
					far += 1
		print("GDGS-SORT n=%d fraction=%.2f far=%d (%.1f%%) took=%.1fms" % [n, fraction, far, 100.0 * far / maxi(n, 1), _last_sort_ms])

func poll() -> bool:
	if _task_id == -1:
		return false
	if not WorkerThreadPool.is_task_completed(_task_id):
		return false
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	_front = 1 - _front
	_has_front = true
	return true

func flush() -> void:
	if _task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
