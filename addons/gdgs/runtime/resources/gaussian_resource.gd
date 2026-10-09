@tool
@icon("res://addons/gdgs/editor/icons/gaussian_resource.svg")
extends Resource
class_name GaussianResource

# GPU-ready std430 layout.
# Each splat occupies 60 float32 values (240 bytes).
@export var point_count: int = 0
@export var point_data_float: PackedFloat32Array
@export var point_data_byte: PackedByteArray
@export var xyz: PackedVector3Array
@export var aabb: AABB = AABB()

# SH metadata (not part of the frozen blob): highest non-zero spherical-harmonic
# degree present in the data. 0 = DC-only (all f_rest_* are exactly 0), 3 = full
# degree-3 view-dependent colour. Stamped at import by gaussian_resource_builder;
# -1 means unknown (legacy/foreign resource), and the renderer then scans the
# blob once at texture-build time.
@export var sh_degree: int = -1
