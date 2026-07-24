extends Node3D

const SPEED = 50.0

@onready var ray_cast_3d: RayCast3D = $RayCast3D
@onready var mesh_instance_3d: MeshInstance3D = $MeshInstance3D
@onready var cpu_particles_3d: CPUParticles3D = $CPUParticles3D
@onready var cpu_particles_3d_2: CPUParticles3D = $CPUParticles3D2

func _ready():
	cpu_particles_3d_2.emitting = true
	# Delete the bullet after 2 seconds to save memory
	await get_tree().create_timer(3.0).timeout
	queue_free()

func _process(delta: float) -> void:
	# Move forward based on where the bullet was pointing when spawned
	# transform.basis.z is "backwards", so we use -SPEED to go "forwards"
	global_position += transform.basis * Vector3(0, 0, -SPEED) * delta
	if ray_cast_3d.is_colliding():
		var target = ray_cast_3d.get_collider()
		if target.has_method("take_damage"):
			target.take_damage(1) # Each bullet takes 25 health
		
		handle_impact() # Your function to play particles and delete bullet

func handle_impact():
	set_process(false) # Stop moving
	mesh_instance_3d.visible = false
	cpu_particles_3d.emitting = true
	await get_tree().create_timer(1.0).timeout
	queue_free()
