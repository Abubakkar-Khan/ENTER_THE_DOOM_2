@tool
extends MeshInstance3D

# --- DEBUG CONTROLS ---
@export var regenerate_button: bool = false:
	set(val):
		if val:
			print("--- Force Regenerate Clicked ---")
			update_mesh()
		regenerate_button = false 

@export var debug_logs: bool = true

@export_range(0.1, 10.0, 0.1) var noise_frequency := 1.0
@onready var nav_region: NavigationRegion3D = $"../NavigationRegion3D"
@export var lava_level: float = 0.0  # Y-value below which is lava


# --- REFERENCES ---
# We keep this as you requested. 
# NOTE: In @tool scripts, onready might not be ready when you drag sliders, 
# so we handle that in update_mesh below.
#@onready var static_body_3d: StaticBody3D = $"../StaticBody3D"
#@onready var static_body_3d: StaticBody3D = $"../NavigationRegion3D/StaticBody3D"
var static_body_3d: StaticBody3D


# --- TERRAIN SETTINGS ---
const size := 256.0

@export_range(4, 2560, 4) var resolution := 32:
	set(new_resolution):
		resolution = new_resolution
		update_mesh()

@export var noise : FastNoiseLite:
	set(new_noise):
		noise = new_noise
		if noise and not noise.changed.is_connected(update_mesh):
			noise.changed.connect(update_mesh)
		update_mesh()
			
@export_range(4.0, 256.0, 4.0) var height := 64.0:
	set(new_height):
		height = new_height
		if material_override:
			material_override.set_shader_parameter("height", height * 2.0)
		update_mesh()

# --- MATH FUNCTIONS ---
@export_range(0.0, 1.0) var falloff_strength : float = 1.0

func get_height(x: float, z: float) -> float:
	if not noise: return 0.0
	
	# 1. Normalize to -1.0 to 1.0
	var nx = x / (size / 2.0)
	var nz = z / (size / 2.0)
	
	# 2. SQUARE FALLOFF: This protects the center area
	# Using max(abs()) creates a square mask instead of a circle
	var dist = max(abs(nx), abs(nz))
	
	# 3. TIGHT MASK: Keep 90% of the map perfectly flat
	# Only start sinking when we are at 0.9 (90% away from center)
	var sink = smoothstep(0.8, 1.0, dist) 
	
	# 4. Apply Height
	var base_h = noise.get_noise_2d(x * noise_frequency, z * noise_frequency) * height
	
	# We subtract height only at the very extreme edges
	return base_h - (sink * height * 1.2)
		
func get_normal(x: float, y:float) -> Vector3:
	var epsilon := size / resolution
	var normal := Vector3 (
		(get_height(x + epsilon, y) - get_height(x - epsilon, y)) / (2.0 * epsilon),
		1.0,
		(get_height(x, y + epsilon) - get_height(x, y - epsilon)) / (2.0 * epsilon),
	)
	return normal.normalized()

# --- MAIN LOGIC ---
func update_mesh() -> void:	
	# Safety check: Don't run if not in scene tree
	if not is_inside_tree(): return

	if debug_logs: print("Generating Mesh...")

	# 1. GENERATE VISUAL MESH
	var plane := PlaneMesh.new()
	plane.subdivide_depth = resolution
	plane.subdivide_width = resolution
	plane.size = Vector2(size, size)
	
	var plane_arrays := plane.get_mesh_arrays()
	var vertex_array : PackedVector3Array = plane_arrays[ArrayMesh.ARRAY_VERTEX]
	var normal_array : PackedVector3Array = plane_arrays[ArrayMesh.ARRAY_NORMAL]
	var tangent_array : PackedFloat32Array = plane_arrays[ArrayMesh.ARRAY_TANGENT]
	
	for i:int in vertex_array.size():
		var vertex := vertex_array[i]
		var normal := Vector3.UP
		var tangent := Vector3.RIGHT
		if noise:
			vertex.y = get_height(vertex.x, vertex.z)
	
			# Pillars to the end
			if vertex.y >= 7:
				vertex.y = 200  # push far down so nav mesh ignores it
			
			#
			normal = get_normal(vertex.x, vertex.z)
			var t_cross = normal.cross(Vector3.UP)
			if t_cross.length_squared() > 0.001:
				tangent = t_cross.normalized()
				
		vertex_array[i] = vertex
		normal_array[i] = normal
		tangent_array[4 * i] = tangent.x
		tangent_array[4 * i + 1] = tangent.y
		tangent_array[4 * i + 2] = tangent.z
		tangent_array[4 * i + 3] = 1.0 
	
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plane_arrays)
	mesh = array_mesh
	
	# 2. COLLISION LOGIC
	
	# FIX: If @onready hasn't grabbed the node yet (common in Tool scripts), grab it manually.
	var target_body := get_node_or_null("../NavigationRegion3D/StaticBody3D") as StaticBody3D


	if target_body:
		if debug_logs: print("Found StaticBody, attempting collision update...")
		
		# A. CLEANUP OLD SHAPES
		for child in target_body.get_children():
			if child.name == "GeneratedTerrainShape":
				target_body.remove_child(child)
				child.queue_free()
		
		# B. CREATE NEW SHAPE
		var trimesh_shape = array_mesh.create_trimesh_shape()
		var collision_node = CollisionShape3D.new()
		collision_node.name = "GeneratedTerrainShape"
		collision_node.shape = trimesh_shape
		
		# C. ATTACH TO PARENT
		collision_node.transform = Transform3D.IDENTITY
		target_body.add_child(collision_node)
		collision_node.set_deferred("disabled", false)
		collision_node.force_update_transform()

		
		# D. SET OWNER (CRITICAL)
		if Engine.is_editor_hint():
			var root = get_tree().edited_scene_root
			if root:
				collision_node.owner = root
				
	# 3. NAVIGATION LOGIC

	var nav = nav_region
	if nav == null:
		nav = get_node_or_null("../NavigationRegion3D")

	if nav and nav.navigation_mesh:
		if debug_logs: print("Baking navigation mesh...")
		nav.call_deferred("bake_navigation_mesh")
		print("NAV MESH Generated/ Baked")
	else:
		if debug_logs: print("WARNING: NavigationRegion3D or NavigationMesh not found.")

	# 4. FORCE NAVIGATION SERVER UPDATE
	if Engine.is_editor_hint():
		var world := get_world_3d()
		if world:
			NavigationServer3D.map_force_update(world.navigation_map)
