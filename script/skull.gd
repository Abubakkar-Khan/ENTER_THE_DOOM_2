extends CharacterBody3D
## Skull
## Owns its own movement, formation position, separation, rotation, and
## death. Reads swarm_center / is_attacking / formation_compression off
## the Spawner each frame — nothing is pushed into it.

signal exploded(position: Vector3)

@export var health: float = 1.0
@export var attack_range: float = 2.0
@export var explosion_radius: float = 2.0
@export var explosion_damage: float = 25.0

@export var glide_follow_speed: float = 20.0
@export var attack_follow_speed: float = 45.0
@export var turn_speed: float = 4.0

# If your model faces the wrong way, set this instead of touching rotation code.
@export var model_forward_correction: float = 0.0

# ─── Crescent formation (the one formation this swarm uses) ───
@export var crescent_arc_angle: float = PI * 0.8
@export var crescent_horizontal_radius: float = 20.0
@export var crescent_depth_radius: float = 10.0
@export var crescent_vertical_spread: float = 5.0

# ─── Separation from nearby skulls ───
@export var separation_radius: float = 2.5
@export var separation_strength: float = 10.0

enum State { FORMATION, EXPLODING }

var state: State = State.FORMATION
var spawner: Node = null
var player: Node3D = null
var slot_index: int = -1
var formation_offset: Vector3 = Vector3.ZERO

func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	add_to_group("flying_skulls")
	if player == null:
		player = get_tree().get_first_node_in_group("player")

## Called once by the Spawner right after instancing.
func initialize(swarm_spawner: Node, swarm_player: Node3D, slot: int, formation_size: int) -> void:
	spawner = swarm_spawner
	player = swarm_player
	slot_index = slot
	formation_offset = _compute_crescent_offset(slot, formation_size)

func _compute_crescent_offset(slot: int, total: int) -> Vector3:
	var t: float = float(slot) / float(max(total - 1, 1))
	var angle: float = -crescent_arc_angle * 0.5 + t * crescent_arc_angle
	var x: float = sin(angle) * crescent_horizontal_radius
	var y: float = cos(angle) * crescent_vertical_spread - crescent_vertical_spread
	var z: float = cos(angle) * crescent_depth_radius
	return Vector3(x, y, z)

func _physics_process(delta: float) -> void:
	if state == State.EXPLODING:
		return

	if player == null:
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return  # genuinely nothing to fly toward yet

	if global_position.distance_to(player.global_position) <= attack_range:
		explode()
		return

	var target: Vector3 = _current_target()
	var speed: float = _current_speed()

	var steer: Vector3 = (target - global_position).normalized() * speed
	steer += _separation_force()

	velocity = velocity.lerp(steer, turn_speed * delta)
	move_and_slide()

	for i in range(get_slide_collision_count()):
		if get_slide_collision(i).get_collider() == player:
			explode()
			return

	_update_rotation(delta)

func _current_target() -> Vector3:
	if spawner == null:
		# No spawner assigned (e.g. testing this skull alone in the scene) —
		# fly straight at the player instead of sitting frozen.
		return player.global_position
	var scale: float = lerp(1.0, 0.3, spawner.formation_compression)
	return spawner.swarm_center + formation_offset * scale

func _current_speed() -> float:
	if spawner != null and spawner.is_attacking:
		return attack_follow_speed
	return glide_follow_speed

func _separation_force() -> Vector3:
	var push: Vector3 = Vector3.ZERO
	for other in get_tree().get_nodes_in_group("flying_skulls"):
		if other == self or not is_instance_valid(other):
			continue
		var to_self: Vector3 = global_position - other.global_position
		var dist: float = to_self.length()
		if dist > 0.001 and dist < separation_radius:
			push += (to_self / dist) * (separation_radius - dist)
	return push * separation_strength

func _update_rotation(delta: float) -> void:
	if velocity.length() <= 1.0:
		return
	var face_dir: Vector3 = velocity.normalized()
	var target_basis: Basis = Basis.looking_at(-face_dir, Vector3.UP)
	target_basis = target_basis.rotated(Vector3.UP, model_forward_correction)
	transform.basis = transform.basis.slerp(target_basis, turn_speed * delta)

func take_damage(amount: float) -> void:
	if state == State.EXPLODING:
		return
	health -= amount
	if health <= 0:
		explode()

func explode() -> void:
	if state == State.EXPLODING:
		return
	state = State.EXPLODING

	if spawner and spawner.has_method("notify_skull_died"):
		spawner.notify_skull_died(slot_index)

	if player and player.has_method("add_score"):
		player.add_score(10)

	if player and global_position.distance_to(player.global_position) <= explosion_radius:
		if player.has_method("take_damage"):
			player.take_damage(explosion_damage)
		elif player.has_method("apply_damage"):
			player.apply_damage(explosion_damage)

	if has_node("Sketchfab_Scene"):
		$Sketchfab_Scene.visible = false
	if has_node("MeshInstance3D"):
		$MeshInstance3D.visible = false

	var particles := get_node_or_null("death_particles")
	if particles is CPUParticles3D:
		particles.emitting = true

	var snd := get_node_or_null("explosion_sound")
	if snd:
		snd.play()

	for shape in find_children("*", "CollisionShape3D"):
		shape.set_deferred("disabled", true)

	set_physics_process(false)
	emit_signal("exploded", global_position)

	await get_tree().create_timer(1.0).timeout
	queue_free()
