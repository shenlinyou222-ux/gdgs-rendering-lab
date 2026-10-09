@tool
extends RefCounted
class_name GaussianRenderer

const RenderingDeviceContext := preload("res://addons/gdgs/runtime/render/compute/gaussian_rendering_device_context.gd")
const RADIX := 256
const MAX_SORT_ELEMENTS_PER_SPLAT := 10

# --- A/B switches (research/16) -------------------------------------------------
# O1: reject pixels outside the splat's screen footprint inside the tile loop.
const SETTING_SUBPIXEL_PRUNE := "gdgs/opt/compute_subpixel_prune"
# Radius multiplier used by O1 (2.0 => truncated at 5 sigma, i.e. bit-lossless
# against the 2.5-sigma tile truncation the projection already applies).
const SETTING_PRUNE_SCALE := "gdgs/opt/compute_prune_scale"
# O3: reuse the previous frame's sorted pairs while the view barely moves.
const SETTING_REUSE_SORT := "gdgs/opt/compute_reuse_sort"
const SETTING_RESORT_DEG := "gdgs/opt/compute_resort_deg"
const SETTING_RESORT_POS := "gdgs/opt/compute_resort_pos"
# Animated instances (swim wave) are re-projected every frame by default, because
# the wave is applied in the projection pass, not in the vertex stage.
const SETTING_REUSE_ANIMATED := "gdgs/opt/compute_reuse_animated"

func _prune_scale() -> float:
	if not bool(ProjectSettings.get_setting(SETTING_SUBPIXEL_PRUNE, false)):
		return 0.0
	return maxf(float(ProjectSettings.get_setting(SETTING_PRUNE_SCALE, 2.0)), 0.05)

func render_for_compositor(
	state_cache: GaussianGpuStateCache,
	scene_registry: GaussianSceneRegistry,
	texture_size: Vector2i,
	camera_transform: Transform3D,
	camera_projection: Projection,
	camera_world_position: Vector3,
	depth_capture_alpha: float = 0.5
) -> Dictionary:
	state_cache.flush_pending_cleanup()

	if not scene_registry.has_gpu_data():
		if state_cache.has_render_states():
			state_cache.cleanup_all()
		return {}

	var point_count := scene_registry.get_point_count()
	var safe_size := Vector2i(maxi(texture_size.x, 1), maxi(texture_size.y, 1))
	var state = state_cache.get_or_create_render_state(safe_size)
	_update_camera_from_transform(state, camera_transform, camera_projection)
	state.camera_world_position = camera_world_position
	state.depth_capture_alpha = clampf(depth_capture_alpha, 0.0, 1.0)

	var unique_data_size := scene_registry.get_point_data_byte().size()

	if state.context == null or state.needs_gpu_rebuild:
		state_cache.rebuild_gpu_state(state, point_count, unique_data_size, scene_registry.get_instance_count())
	if state.context == null:
		return {}

	# O3: the pair buffer on the GPU is only invalidated by a configuration change
	# (pair budget) or by a camera that moved enough to matter.
	var budget := GaussianGpuStateCache.sort_budget()
	var signature := "b%d" % budget
	if state.sort_signature != signature:
		state.sort_signature = signature
		state.sort_valid = false

	var reuse_enabled := bool(ProjectSettings.get_setting(SETTING_REUSE_SORT, false))
	var pending_upload: bool = state.needs_splat_upload or state.needs_instance_upload or state.needs_relight_upload
	var full: bool = true
	if reuse_enabled and state.sort_valid and not pending_upload:
		full = _view_needs_resort(state, camera_transform, camera_projection, scene_registry)

	if not full:
		# Cheap frame: the pairs, the tile bounds and the per-splat records are all
		# still valid for this camera, so only the rasterizer runs.
		_render_pass(state)
		return _output(state)

	if state.needs_splat_upload:
		state_cache.upload_splats(state, scene_registry.get_point_data_byte(), scene_registry.get_splat_instance_ids_byte())
		state_cache.upload_splat_lighting(state, scene_registry.get_splat_lighting_byte())
	if state.needs_instance_upload:
		state_cache.upload_instance_transforms(state, scene_registry.get_instance_transforms_byte())
	if state.needs_relight_upload:
		state_cache.upload_relight(
			state, scene_registry.get_light_rig_byte(), scene_registry.get_instance_relight_byte(),
			scene_registry.get_instance_wave_byte()
		)

	if state.camera_push_constants.is_empty():
		return {}

	_rasterize_state(state, point_count, scene_registry.get_light_count())
	state.sort_valid = true
	state.last_forward = -camera_transform.basis.z
	state.last_camera_pos = camera_transform.origin
	state.last_camera_projection = camera_projection
	return _output(state)

## The compositor only ever wants the two texture RIDs; both paths return the same.
func _output(state) -> Dictionary:
	if state.descriptors.has("render_texture") and state.descriptors.has("depth_texture"):
		return {
			"color_alpha_texture": state.descriptors["render_texture"].rid,
			"depth_texture": state.descriptors["depth_texture"].rid
		}
	return {}

## O3 decision: does the visible order/records really have to be rebuilt?
## Mirrors the tolerance the Raster backend has always accepted (it re-sorts one
## node at a time past ~1 degree and reuses the far block in between), but derived
## from the camera instead of the node.
func _view_needs_resort(state, camera_transform: Transform3D, camera_projection: Projection, scene_registry) -> bool:
	if camera_projection != state.last_camera_projection:
		return true
	var forward := -camera_transform.basis.z
	var cos_threshold := cos(deg_to_rad(maxf(float(ProjectSettings.get_setting(SETTING_RESORT_DEG, 0.5)), 0.0)))
	if forward.dot(state.last_forward) < cos_threshold:
		return true
	var centre: Vector3 = scene_registry.get_scene_center()
	var reference := maxf((camera_transform.origin - centre).length(), 1e-3)
	var pos_ratio := maxf(float(ProjectSettings.get_setting(SETTING_RESORT_POS, 0.01)), 0.0)
	if (camera_transform.origin - state.last_camera_pos).length() > reference * pos_ratio:
		return true
	if scene_registry.has_animated_instances() and not bool(ProjectSettings.get_setting(SETTING_REUSE_ANIMATED, false)):
		return true
	return false

func _rasterize_state(state, point_count: int, light_count: int) -> void:
	if state.context == null:
		return

	# Uniforms block (binding 8) member offsets as the SPIR-V actually lays them
	# out (probed from inside the shader): camera_pos 0, time 12, dims 16-23,
	# point_count 24, light_count 28, sh_degree 32 — i.e. PACKED, no std140
	# 16-byte vec3 padding. The block's total size still rounds up to 48 bytes,
	# which is why a 36-byte buffer is rejected while the members are contiguous.
	# O5 added a 10th member (sort_budget) at offset 36, still inside the 48-byte
	# block; the buffer is 64B so the padded copy fits.
	var uniforms := RenderingDeviceContext.create_push_constant([
		state.camera_world_position.x,
		state.camera_world_position.y,
		state.camera_world_position.z,
		Time.get_ticks_msec() * 1e-3,
		state.texture_size.x,
		state.texture_size.y,
		point_count,
		# The trailing slot used to be padding; it now carries the active light
		# count, which is what bounds the projection shader's relight loop.
		light_count,
		# S1: SH degree for the projection shader's DC-only fast path. The bench
		# harness forces gdgs/opt/sh_dc_force; when auto, the conservative full
		# path is kept (Compute is not the active backend yet — see M5-D).
		maxi(int(ProjectSettings.get_setting("gdgs/opt/sh_dc_force", -1)), 0),
		# O5: pairs per splat the sort buffers were sized with; the projection pass
		# clamps its tile rect to this so the two can never disagree.
		GaussianGpuStateCache.sort_budget(),
		0.0,  # trailing pad to the block size
		0.0,
		0.0
	])
	state.context.device.buffer_update(state.descriptors["uniforms"].rid, 0, uniforms.size(), uniforms)
	# Clear the histogram. The default clears the whole allocation (pair counter +
	# global + every partition histogram); O6 clears only the pair counter and the
	# global histogram, because the upsweep rewrites the partition histogram of
	# every partition the spine reads in the same frame — which is what makes the
	# O(N*budget)-sized clear unnecessary. (research/15 M5-D: a partial clear of
	# only 4 + 4*RADIX*4 bytes used to corrupt the sort; that was before the
	# upsweep was made to write, rather than accumulate into, the partition
	# histograms, so O6 keeps its own switch.)
	var clear_bytes: int = state.histogram_bytes
	if GaussianGpuStateCache.lean_clear_enabled() and state.histogram_clear_bytes > 0:
		clear_bytes = state.histogram_clear_bytes
	state.context.device.buffer_clear(state.descriptors["histogram"].rid, 0, clear_bytes)
	state.context.device.buffer_clear(state.descriptors["tile_bounds"].rid, 0, state.tile_dims.x * state.tile_dims.y * 2 * 4)

	var compute_list: int = state.context.compute_list_begin()
	state.pipelines["gsplat_projection"].call(state.context, compute_list, state.camera_push_constants)
	state.context.compute_list_end()


	var budget := GaussianGpuStateCache.sort_budget()
	compute_list = state.context.compute_list_begin()
	for radix_shift_pass in range(4):
		var sort_push_constant := RenderingDeviceContext.create_push_constant([
			radix_shift_pass,
			point_count * budget * (radix_shift_pass % 2),
			point_count * budget * (1 - (radix_shift_pass % 2)),
			0
		])
		state.pipelines["radix_sort_upsweep"].call(state.context, compute_list, sort_push_constant, [], state.descriptors["grid_dimensions"].rid, 0)
		state.pipelines["radix_sort_spine"].call(state.context, compute_list, sort_push_constant)
		state.pipelines["radix_sort_downsweep"].call(state.context, compute_list, sort_push_constant, [], state.descriptors["grid_dimensions"].rid, 0)
	state.context.compute_list_end()

	compute_list = state.context.compute_list_begin()
	state.pipelines["gsplat_boundaries"].call(state.context, compute_list, PackedByteArray(), [], state.descriptors["grid_dimensions"].rid, 3 * 4)
	state.context.compute_list_end()


	_render_pass(state)

## Rasterize pass only: reads the pair buffer + tile bounds + per-splat records as
## they are on the GPU. Safe to run on its own (O3).
func _render_pass(state) -> void:
	if state.context == null:
		return
	var prune_scale := _prune_scale()
	var compute_list: int = state.context.compute_list_begin()
	state.pipelines["gsplat_render"].call(
		state.context,
		compute_list,
		RenderingDeviceContext.create_push_constant([0.0, -1, state.depth_capture_alpha, prune_scale])
	)
	state.context.compute_list_end()


func _update_camera_from_transform(state, camera_transform: Transform3D, camera_projection: Projection) -> void:
	var view := Projection(camera_transform.affine_inverse())
	if view != state.camera_view or camera_projection != state.camera_projection:
		state.camera_view = view
		state.camera_projection = camera_projection
		state.camera_push_constants = RenderingDeviceContext.create_push_constant(
			_projection_to_column_major_floats(view) + _projection_to_column_major_floats(camera_projection)
		)

func _projection_to_column_major_floats(matrix: Projection) -> Array:
	return [
		matrix.x[0], matrix.x[1], matrix.x[2], matrix.x[3],
		matrix.y[0], matrix.y[1], matrix.y[2], matrix.y[3],
		matrix.z[0], matrix.z[1], matrix.z[2], matrix.z[3],
		matrix.w[0], matrix.w[1], matrix.w[2], matrix.w[3]
	]
