extends Node3D

const SPEED = 200.0

@onready var ray_cast_3d: RayCast3D = $RayCast3D
@onready var mesh_instance_3d: MeshInstance3D = $MeshInstance3D
@onready var cpu_particles_3d: CPUParticles3D = $CPUParticles3D
@onready var cpu_particles_3d_2: CPUParticles3D = $CPUParticles3D2

func _ready():
	cpu_particles_3d_2.emitting = true

	await get_tree().create_timer(10.0).timeout
	queue_free()

func _process(delta: float) -> void:
	# Make the ray reach as far as the bullet moves this frame
	ray_cast_3d.target_position = Vector3(0, 0, -SPEED * delta)
	ray_cast_3d.force_raycast_update()

	# Check hit BEFORE moving
	if ray_cast_3d.is_colliding():
		var target = ray_cast_3d.get_collider()

		if target.has_method("take_damage"):
			target.take_damage(1)

		handle_impact()
		return

	# Move bullet
	global_position += -transform.basis.z * SPEED * delta

func handle_impact():
	set_process(false)
	mesh_instance_3d.visible = false
	cpu_particles_3d.emitting = true

	await get_tree().create_timer(1.0).timeout
	queue_free()
