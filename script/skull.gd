extends CharacterBody3D

signal skull_died

@export var health: float = 2.0
@export var hover_speed: float = 5.0
@export var charge_speed: float = 16.0
@export var attack_range: float = 2.0
@export var charge_range: float = 15.0
@export var orbit_radius: float = 8.0
@export var jitter_strength: float = 4.0
@export var rotation_speed: float = 10.0
@export var charge_cooldown: float = 1.2
@export var charge_duration: float = 0.35
@export var swarm_separation: float = 3.0

@onready var sketchfab_scene: Node3D = $Sketchfab_Scene
@onready var death_particles: CPUParticles3D = $death_particles
@onready var explosion_sound: AudioStreamPlayer3D = $explosion_sound

var player = null
var time_alive: float = 0.0
var cooldown_timer: float = 0.0
var charge_timer: float = 0.0
var is_charging: bool = false
var charge_direction: Vector3 = Vector3.ZERO
var orbit_offset: Vector3 = Vector3.ZERO

func _ready():
	player = get_tree().root.find_child("ProtoController", true, false)
	
	# Random orbit offset so multiple skulls don't stack
	orbit_offset = Vector3(
		randf_range(-orbit_radius, orbit_radius),
		randf_range(-3.0, 3.0),
		randf_range(-orbit_radius, orbit_radius)
	)

func _physics_process(delta):
	if not player or health <= 0:
		return
	
	time_alive += delta
	
	if cooldown_timer > 0:
		cooldown_timer -= delta
	
	var to_player = player.global_position - global_position
	var dist = to_player.length()
	
	# State machine
	if is_charging:
		process_charge(delta, dist)
	elif dist <= charge_range and dist > attack_range and cooldown_timer <= 0:
		start_charge(to_player)
	else:
		process_hover(delta, to_player, dist)
	
	# Full 3D rotation toward movement direction
	face_movement_direction(delta)
	
	move_and_slide()

func start_charge(to_player: Vector3):
	is_charging = true
	charge_timer = charge_duration
	cooldown_timer = charge_cooldown + randf_range(-0.2, 0.3)
	
	# Aim at player with slight random inaccuracy (Devil Daggers feel)
	charge_direction = to_player.normalized()
	charge_direction += Vector3(
		randf_range(-0.25, 0.25),
		randf_range(-0.15, 0.15),
		randf_range(-0.25, 0.25)
	)
	charge_direction = charge_direction.normalized()

func process_charge(delta, dist):
	charge_timer -= delta
	velocity = charge_direction * charge_speed
	
	# End charge if timer expires or we get close
	if charge_timer <= 0 or dist <= attack_range:
		is_charging = false
		velocity *= 0.3  # Brief slowdown after charge

func process_hover(delta, to_player: Vector3, dist: float):
	var target_pos: Vector3
	
	if dist > orbit_radius * 1.5:
		# Far away: move toward player aggressively
		target_pos = to_player.normalized() * hover_speed
	else:
		# Close/mid range: orbit erratically around player
		var orbit_point = player.global_position + orbit_offset
		orbit_offset = orbit_offset.rotated(Vector3.UP, delta * 1.5)  # Orbit slowly
		orbit_offset.y = sin(time_alive * 2.0 + orbit_offset.x) * 3.0  # Bob up/down
		
		var to_orbit = orbit_point - global_position
		target_pos = to_orbit.normalized() * hover_speed
	
	# Erratic jitter (the Devil Daggers twitch)
	var jitter = Vector3(
		sin(time_alive * 11.7) * jitter_strength,
		cos(time_alive * 8.3) * jitter_strength,
		cos(time_alive * 13.1) * jitter_strength
	)
	
	# Swarm separation — push away from other skulls
	var separation = get_separation_force()
	
	velocity = target_pos + jitter + separation
	
	# Cap speed when not charging
	if velocity.length() > hover_speed * 1.5:
		velocity = velocity.normalized() * hover_speed * 1.5

func get_separation_force() -> Vector3:
	var force = Vector3.ZERO
	var skulls = get_tree().get_nodes_in_group("flying_skulls")
	
	for skull in skulls:
		if skull == self:
			continue
		var diff = global_position - skull.global_position
		var dist = diff.length()
		if dist < swarm_separation and dist > 0.01:
			force += diff.normalized() * (swarm_separation - dist) * 5.0
	
	return force

func face_movement_direction(delta):
	# Face where we're moving, or face player if idle
	var look_target: Vector3
	if velocity.length() > 0.5:
		look_target = global_position + velocity
	else:
		look_target = player.global_position
	
	var target_transform = transform.looking_at(look_target, Vector3.UP)
	transform = transform.interpolate_with(target_transform, rotation_speed * delta)

func take_damage(amount: float):
	health -= amount
	print("Skull health: ", health)
	
	if health <= 0:
		die()
	else:
		# Knockback from hit
		is_charging = false
		velocity = -global_position.direction_to(player.global_position) * 8.0

func die():
	health = 0
	sketchfab_scene.visible = false
	if death_particles and not death_particles.emitting:
		death_particles.emitting = true
	if explosion_sound and not explosion_sound.playing:
		explosion_sound.play()
	
	$CollisionShape3D.set_deferred("disabled", true)
	set_physics_process(false)
	
	emit_signal("skull_died")
	await get_tree().create_timer(1.0).timeout
	queue_free()
