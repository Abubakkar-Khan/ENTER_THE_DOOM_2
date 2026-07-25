extends CharacterBody3D

signal exploded(position: Vector3)

@export var health: float = 1.0
@export var speed: float = 13.0
@export var turn_speed: float = 10.0
@export var detection_range: float = 80.0
@export var attack_range: float = 1.5
@export var explosion_radius: float = 2.0
@export var explosion_damage: float = 25.0
@export var separation_radius: float = 2.0
@export var separation_force: float = 6.0

var player: Node3D = null
var time_alive: float = 0.0
var drift_seed: float = 0.0
var is_exploding: bool = false

func _ready():
	motion_mode = MOTION_MODE_FLOATING
	add_to_group("flying_skulls")
	_find_player()
	drift_seed = randf_range(0.0, 100.0)

func _find_player():
	player = get_tree().get_first_node_in_group("player")
	if player:
		return
	var names: Array[String] = ["ProtoController", "Player", "FPSController", "PlayerBody"]
	for n in names:
		player = get_tree().root.find_child(n, true, false)
		if player:
			return
	push_warning("FlyingSkull: No player found! Add player to 'player' group.")

func _physics_process(delta):
	if is_exploding or player == null:
		return
	
	time_alive += delta
	
	var to_player: Vector3 = player.global_position - global_position
	var dist: float = to_player.length()
	
	# EXPLODE ON TOUCH
	if dist <= attack_range:
		explode()
		return
	
	# Too far: do nothing
	if dist > detection_range:
		return
	
	# === HOMING ===
	var dir: Vector3 = to_player.normalized()
	
	# === TINY DRIFT ===
	var drift: Vector3 = Vector3(
		sin(time_alive * 3.1 + drift_seed),
		cos(time_alive * 2.8 + drift_seed),
		cos(time_alive * 3.7 + drift_seed)
	) * 0.2
	dir += drift
	
	# === SEPARATION (push away from other skulls only) ===
	for skull in get_tree().get_nodes_in_group("flying_skulls"):
		if skull == self or not is_instance_valid(skull):
			continue
		var skull_node: Node3D = skull
		var offset: Vector3 = global_position - skull_node.global_position
		var d: float = offset.length()
		if d < separation_radius and d > 0.01:
			var push: float = (separation_radius - d) / separation_radius
			dir += offset.normalized() * push * separation_force
	
	dir = dir.normalized()
	
	# === MISSILE MOVEMENT ===
	velocity = velocity.lerp(dir * speed, turn_speed * delta)
	move_and_slide()
	
	# Backup ram check
	for i in get_slide_collision_count():
		if get_slide_collision(i).get_collider() == player:
			explode()
			return
	
	# === FACE AWAY FROM PLAYER ===
	look_at(player.global_position, Vector3.UP)
	rotate_y(PI)
	
	# === HOVER BOB ===
	if has_node("Sketchfab_Scene"):
		var mesh: Node3D = $Sketchfab_Scene
		mesh.position.y = sin(time_alive * 2.0) * 0.15

func take_damage(amount: float):
	if is_exploding:
		return
	health -= amount
	if health <= 0:
		explode()

func explode():
	if is_exploding:
		return
	is_exploding = true
	
	if player:
		player.add_score(10)
	
	if player and global_position.distance_to(player.global_position) <= explosion_radius:
		if player.has_method("take_damage"):
			player.take_damage(explosion_damage)
		elif player.has_method("apply_damage"):
			player.apply_damage(explosion_damage)
	
	if has_node("Sketchfab_Scene"):
		$Sketchfab_Scene.visible = false
		$MeshInstance3D.visible = false
	
	var particles = get_node_or_null("death_particles")
	if particles and particles is CPUParticles3D:
		particles.emitting = true
	
	var snd = get_node_or_null("explosion_sound")
	if snd:
		snd.play()
	
	for child in get_children():
		if child is CollisionShape3D:
			child.set_deferred("disabled", true)
	
	set_physics_process(false)
	emit_signal("exploded", global_position)
	await get_tree().create_timer(1.0).timeout
	queue_free()
	
	
