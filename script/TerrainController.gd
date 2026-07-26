#@tool
extends Node3D

# --- REFERENCES ---
# Assign these in the Inspector by clicking "Assign" and picking the child nodes
@export var mesh_instance: MeshInstance3D
@export var static_body: StaticBody3D

# --- SETTINGS ---
@export var regenerate: bool = false:
	set(val):
		if val: generate_terrain()
		regenerate = false

const SIZE := 256.0

@export_range(4, 2560, 4) var resolution := 32:
	set(val):
		resolution = val
		generate_terrain()

@export var height := 64.0:
	set(val):
		height = val
		generate_terrain()
	
@export var noise: FastNoiseLite:
	set(val):
		noise = val
		if noise and not noise.changed.is_connected(generate_terrain):
			noise.changed.connect(generate_terrain)
		generate_terrain()

@onready var pause_menu: CanvasLayer = $Pause

func _ready():
	pause_menu.hide()
	
# --- MATH HELPER ---
func get_height(x: float, y: float) -> float:
	if not noise: return 0.0
	return noise.get_noise_2d(x, y) * height

func get_normal(x: float, y: float) -> Vector3:
	var eps = SIZE / float(resolution)
	var h_l = get_height(x - eps, y)
	var h_r = get_height(x + eps, y)
	var h_d = get_height(x, y - eps)
	var h_u = get_height(x, y + eps)
	
	# Calculate normal vector
	var normal = Vector3(
		(h_l - h_r) / (2.0 * eps),
		1.0,
		(h_d - h_u) / (2.0 * eps)
	)
	return normal.normalized()

# --- MAIN GENERATION ---
func generate_terrain():
	# 1. Safety Checks
	if not is_inside_tree(): return
	if not mesh_instance or not static_body:
		print("TerrainController: Please assign MeshInstance and StaticBody in Inspector")
		return

	# 2. Build Mesh Data
	var plane = PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	plane.subdivide_width = resolution
	plane.subdivide_depth = resolution
	
	var arrays = plane.get_mesh_arrays()
	var verts = arrays[ArrayMesh.ARRAY_VERTEX]
	var norms = arrays[ArrayMesh.ARRAY_NORMAL]
	var tangents = arrays[ArrayMesh.ARRAY_TANGENT]
	
	for i in range(verts.size()):
		var v = verts[i]
		
		# Apply Height
		v.y = get_height(v.x, v.z)
		verts[i] = v
		
		# Apply Normal
		var n = get_normal(v.x, v.z)
		norms[i] = n
		
		# Apply Tangent (Calculated from normal)
		var t_cross = n.cross(Vector3.UP)
		var t_vec = Vector3.RIGHT
		if t_cross.length_squared() > 0.01:
			t_vec = t_cross.normalized()
			
		tangents[i*4] = t_vec.x
		tangents[i*4+1] = t_vec.y
		tangents[i*4+2] = t_vec.z
		tangents[i*4+3] = 1.0

	# 3. Commit Mesh to Visual Node
	arrays[ArrayMesh.ARRAY_VERTEX] = verts
	arrays[ArrayMesh.ARRAY_NORMAL] = norms
	arrays[ArrayMesh.ARRAY_TANGENT] = tangents
	
	var arr_mesh = ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	mesh_instance.mesh = arr_mesh

	# 4. Create Collision on Physics Node
	update_collision(arr_mesh)

func update_collision(mesh_data: ArrayMesh):
	# Clear old children from StaticBody
	for child in static_body.get_children():
		child.free() # immediate delete in tool mode is often cleaner
		
	# Create Shape
	var shape = mesh_data.create_trimesh_shape()
	var col_node = CollisionShape3D.new()
	col_node.shape = shape
	col_node.name = "TerrainCollider"
	
	static_body.add_child(col_node)
	
	# CRITICAL: Set owner so it appears in Scene Tree
	if Engine.is_editor_hint():
		col_node.owner = get_tree().edited_scene_root
		

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		get_tree().paused = !get_tree().paused

		if get_tree().paused:
			pause_menu.show()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			pause_menu.hide()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
