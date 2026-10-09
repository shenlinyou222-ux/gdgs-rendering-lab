@tool
extends RefCounted

## CPU counting sort producing a back-to-front splat order for the Raster backend.
##
## Reads only positions (GaussianResource.xyz); it never touches the 60-float
## blob. The sort key is `dot(center, view_dir_local)` — the splat centre
## projected onto the camera forward direction expressed in the splat's local
## space (positions are the recentered local coordinates). Larger key = farther
## into the scene = drawn first, so the result is ordered far→near for standard
## "over" blending.
##
## A single 16-bit counting pass gives 65536 depth buckets across the scene's
## depth range — ample resolution for splatting, O(n + buckets), and cheap enough
## to run every frame the camera moves (on a worker thread; see raster_sort_job).
## Within a bucket, ties keep original index order (stable).
##
## The scatter writes indices straight in the layout the R32F order texture
## wants — float32, padded to the texture's texel count — so the main thread only
## ever hands finished bytes to Image.set_data. This is deliberate: converting
## int→float per splat on the main thread instead cost 23 ms at 1M splats every
## time a sort landed, i.e. a dropped frame per re-sort.

const BUCKET_BITS := 16
const BUCKET_COUNT := 1 << BUCKET_BITS   # 65536

## Sort into a caller-provided buffer to avoid per-frame allocation. `out_order`
## is resized to `texel_count` — the order texture's padded texel count, or -1 for
## exactly xyz.size() — and its first xyz.size() entries are filled with splat
## indices far→near, stored as floats. Padding entries stay 0.0 and are never
## fetched: the shader only reads sorted positions below point_count. Returns the
## same array for convenience.
static func sort_into(xyz: PackedVector3Array, view_dir_local: Vector3, out_order: PackedFloat32Array, texel_count: int = -1) -> PackedFloat32Array:
	return sort_into_aware(xyz, view_dir_local, PackedFloat32Array(), 0.0, out_order, texel_count)

## C1 · distance-aware sort (M4): the `far_fraction` (0..1, 0 = off) of splats
## that were farthest on the previous sort keep their previous relative order,
## and only the remaining near splats are re-sorted. Rationale (research/15 C1):
## for far splats a one-frame-stale order is invisible, so the 408k re-sort cost
## shrinks to (1 - far_fraction) of the splats. `prev_order` is the previous
## far→near order (may be empty when no sort has completed yet, in which case a
## full sort runs). The far/near split adapts every frame: the split key is the
## *current* key of the splat that was last frame's K-th farthest, so the far set
## tracks the camera instead of freezing.
static func sort_into_aware(xyz: PackedVector3Array, view_dir_local: Vector3, prev_order: PackedFloat32Array, far_fraction: float, out_order: PackedFloat32Array, texel_count: int = -1) -> PackedFloat32Array:
	var n := xyz.size()
	var size := maxi(texel_count, n) if texel_count >= 0 else n
	if out_order.size() != size:
		out_order.resize(size)
	if n == 0:
		return out_order

	var dx := view_dir_local.x
	var dy := view_dir_local.y
	var dz := view_dir_local.z

	var keys := PackedFloat32Array()
	keys.resize(n)
	var kmin := INF
	var kmax := -INF
	for i in range(n):
		var p := xyz[i]
		var k := p.x * dx + p.y * dy + p.z * dz
		keys[i] = k
		if k < kmin:
			kmin = k
		if k > kmax:
			kmax = k

	if kmax <= kmin:
		for i in range(n):
			out_order[i] = float(i)
		return out_order

	var far_count := 0
	var threshold := 0.0
	if far_fraction > 0.0 and prev_order.size() >= n:
		# K = the previous far block size; its boundary splat's *current* key is
		# this frame's live threshold (self-adapting as the camera orbits).
		var k := int(float(n) * clampf(far_fraction, 0.0, 1.0))
		k = maxi(k, 1)
		var boundary := clampi(int(prev_order[mini(k - 1, n - 1)] + 0.5), 0, n - 1)
		threshold = keys[boundary]
		for i in range(n):
			if keys[i] >= threshold:
				far_count += 1

	if far_count <= 0:
		# No far reuse (off, first frame, or nothing qualifies): plain full sort.
		# Buckets are cached once per splat so the int() conversion happens a
		# single time instead of once per histogram and once per scatter.
		var scale := float(BUCKET_COUNT - 1) / (kmax - kmin)
		var buckets := PackedInt32Array()
		buckets.resize(n)
		var counts := PackedInt32Array()
		counts.resize(BUCKET_COUNT)
		for i in range(n):
			var b := clampi(int((keys[i] - kmin) * scale), 0, BUCKET_COUNT - 1)
			buckets[i] = b
			counts[b] += 1
		var offset := 0
		for b in range(BUCKET_COUNT - 1, -1, -1):
			var c := counts[b]
			counts[b] = offset
			offset += c
		for i in range(n):
			out_order[counts[buckets[i]]] = float(i)
			counts[buckets[i]] += 1
		return out_order

	if far_count >= n:
		# Everything is far: the previous far→near order IS the answer.
		for j in range(n):
			out_order[j] = prev_order[j]
		return out_order

	# One merged pass over the previous order: extract the far block in its
	# previous relative order AND build a compact near list (splats whose current
	# key fell below the threshold), so the near counting sort below only touches
	# (n - far_count) entries instead of re-walking all n with a skip.
	var far_pos := 0
	var near_count := n - far_count
	var near_list := PackedInt32Array()
	near_list.resize(near_count)
	var near_pos := 0
	for j in range(n):
		var idx := int(prev_order[j] + 0.5)
		if idx >= 0 and idx < n:
			if keys[idx] >= threshold:
				out_order[far_pos] = float(idx)
				far_pos += 1
			else:
				near_list[near_pos] = idx
				near_pos += 1

	# Near block: counting sort over the near subset only, far→near, appended
	# after the far block so the whole array stays back-to-front.
	var scale := float(BUCKET_COUNT - 1) / (kmax - kmin)
	var near_buckets := PackedInt32Array()
	near_buckets.resize(near_count)
	var counts := PackedInt32Array()
	counts.resize(BUCKET_COUNT)
	for j in range(near_count):
		var b := clampi(int((keys[near_list[j]] - kmin) * scale), 0, BUCKET_COUNT - 1)
		near_buckets[j] = b
		counts[b] += 1
	var offset := far_pos
	for b in range(BUCKET_COUNT - 1, -1, -1):
		var c := counts[b]
		counts[b] = offset
		offset += c
	for j in range(near_count):
		out_order[counts[near_buckets[j]]] = float(near_list[j])
		counts[near_buckets[j]] += 1

	return out_order

## Convenience wrapper that allocates a fresh order array.
static func sort(xyz: PackedVector3Array, view_dir_local: Vector3) -> PackedFloat32Array:
	return sort_into(xyz, view_dir_local, PackedFloat32Array())
