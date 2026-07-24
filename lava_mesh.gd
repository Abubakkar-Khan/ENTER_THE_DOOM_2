@tool
extends MeshInstance3D

@export_range(4, 2560, 4) var resolution := 64
@export var size := 256.0
@export var noise_texture: NoiseTexture2D
@export var lava_height := 0.05  # slight offset above terrain
@export var shader_path: String = "res://lava_shader.shader"  # path to your shader

func _ready():
	update_mesh()

func update_mesh():
	# 1. create a plane mesh
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.subdivide_width = resolution
	plane.subdivide_depth = resolution

	var plane_arrays := plane.get_mesh_arrays()
	var vertex_array: PackedVector3Array = plane_arrays[ArrayMesh.ARRAY_VERTEX]
	var normal_array: PackedVector3Array = plane_arrays[ArrayMesh.ARRAY_NORMAL]
	var tangent_array: PackedFloat32Array = plane_arrays[ArrayMesh.ARRAY_TANGENT]

	# 2. add UVs and slight Y offset
	var uv_array := PackedVector2Array()
	uv_array.resize(vertex_array.size())

	for i in vertex_array.size():
		var v = vertex_array[i]
		v.y += lava_height  # offset above terrain
		vertex_array[i] = v

		normal_array[i] = Vector3.UP
		tangent_array[4*i] = 1.0
		tangent_array[4*i+1] = 0.0
		tangent_array[4*i+2] = 0.0
		tangent_array[4*i+3] = 1.0

		uv_array[i] = Vector2(
			(v.x / size) + 0.5,
			(v.z / size) + 0.5
		)

	# 3. assign arrays
	plane_arrays[ArrayMesh.ARRAY_VERTEX] = vertex_array
	plane_arrays[ArrayMesh.ARRAY_NORMAL] = normal_array
	plane_arrays[ArrayMesh.ARRAY_TANGENT] = tangent_array
	plane_arrays[ArrayMesh.ARRAY_TEX_UV] = uv_array

	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plane_arrays)
	mesh = array_mesh

	# 4. assign shader material
	if noise_texture != null and shader_path != "":
		var shader_mat := ShaderMaterial.new()
		shader_mat.shader = load(shader_path)
		shader_mat.set_shader_parameter("noise_tex", noise_texture)
		mesh.surface_set_material(0, shader_mat)
