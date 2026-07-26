extends CharacterBody3D
## Skull — one segment of the flock/dragon.
## CALM: swirls in its own loose orbit around the leader (unique speed,
##   radius and phase per skull) so the flock reads as a living cloud,
##   not a rigid grid.
## WARNING / ATTACK: trails the leader's recent path like a segment of a
##   serpent's body (see Spawner.get_history_position()).
## After an ATTACK ends: scatters outward briefly, then drifts back into
##   its calm orbit on its own.

signal exploded(position: Vector3)

@export var health: float = 1.0
@export var attack_range: float = 2.0
@export var explosion_radius: float = 2.0
@export var explosion_damage: float = 25.0

@export var calm_speed: float = 16.0
@export var warning_speed: float = 40.0
@export var attack_speed: float = 55.0
@export var recover_speed: float = 30.0
@export var turn_speed: float = 5.0
@export var max_bank_angle: float = 0.9    # radians — how far it leans into turns

@export var model_forward_correction: float = 0.0

@export var separation_radius: float = 2.2
@export var separation_strength: float = 9.0

@export var recover_duration: float = 1.6  # scatter time right after an attack pass

const GOLDEN_ANGLE: float = 2.39996323

enum Phase { CALM, WARNING, ATTACK }   # must mirror Spawner.Phase (same order = same ints)
enum State { NORMAL, EXPLODING }

var state: State = State.NORMAL
var spawner: Node = null
var player: Node3D = null
var slot_index: int = -1
var chain_gap_frames: int = 5

# Per-skull calm-orbit personality, derived once from slot_index using the
# golden angle — gives an evenly spread, non-repeating pattern without
# needing real randomness (same trick sunflower seed spirals use).
var _ring_radius: float
var _ring_speed: float
var _ring_phase: float
var _altitude_amp: float
var _altitude_speed: float
var _altitude_phase: float
var _calm_time: float = 0.0

var _last_phase: int = -1
var _recover_timer: float = 0.0
var _scatter_target: Vector3 = Vector3.ZERO

var _prev_flat_dir: Vector3 = Vector3.FORWARD
var _roll: float = 0.0

func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	add_to_group("flying_skulls")
	if player == null:
		player = get_tree().get_first_node_in_group("player")

## Called once by the Spawner right after instancing.
func initialize(swarm_spawner: Node, swarm_player: Node3D, slot: int, gap_frames: int) -> void:
	spawner = swarm_spawner
	player = swarm_player
	slot_index = slot
	chain_gap_frames = gap_frames
	_init_calm_personality()

func _init_calm_personality() -> void:
	var s: float = float(slot_index)
	_ring_radius = 9.0 + fmod(s * 3.3, 9.0)          # ~9..18
	_ring_speed = 0.18 + fmod(s * 0.081, 0.22)        # ~0.18..0.40
	_ring_phase = s * GOLDEN_ANGLE
	_altitude_amp = 2.0 + fmod(s * 1.7, 3.5)          # ~2..5.5
	_altitude_speed = 0.3 + fmod(s * 0.061, 0.35)
	_altitude_phase = s * GOLDEN_ANGLE * 1.5

func _physics_process(delta: float) -> void:
	if state == State.EXPLODING:
		return

	if player == null:
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return

	if global_position.distance_to(player.global_position) <= attack_range:
		explode()
		return

	_calm_time += delta
	_track_phase_change(delta)

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

func _track_phase_change(delta: float) -> void:
	if _recover_timer > 0.0:
		_recover_timer -= delta

	if spawner == null:
		return

	var current_phase: int = spawner.phase
	if current_phase != _last_phase:
		if _last_phase == Phase.ATTACK and current_phase == Phase.CALM:
			_start_recovering()
		_last_phase = current_phase

func _start_recovering() -> void:
	_recover_timer = recover_duration
	var dir: Vector3 = Vector3(
		randf_range(-1.0, 1.0), randf_range(-0.2, 0.6), randf_range(-1.0, 1.0)
	).normalized()
	_scatter_target = global_position + dir * randf_range(7.0, 15.0)

func _current_target() -> Vector3:
	if spawner == null:
		return player.global_position

	if _recover_timer > 0.0:
		return _scatter_target

	if spawner.phase == Phase.CALM:
		return _calm_target()

	# WARNING and ATTACK: trail the leader like a segment of its body
	var delay_frames: int = slot_index * chain_gap_frames
	return spawner.get_history_position(delay_frames)

func _calm_target() -> Vector3:
	var angle: float = _calm_time * _ring_speed + _ring_phase
	var altitude: float = sin(_calm_time * _altitude_speed + _altitude_phase) * _altitude_amp
	return spawner.leader_pos + Vector3(
		cos(angle) * _ring_radius,
		altitude,
		sin(angle) * _ring_radius
	)

func _current_speed() -> float:
	if _recover_timer > 0.0:
		return recover_speed
	if spawner == null:
		return calm_speed
	if spawner.phase == Phase.WARNING:
		return warning_speed
	if spawner.phase == Phase.ATTACK:
		return attack_speed
	return calm_speed

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

	# Bank into turns like a bird/dragon wing tilt
	var flat_dir: Vector3 = Vector3(face_dir.x, 0.0, face_dir.z)
	if flat_dir.length() > 0.01 and _prev_flat_dir.length() > 0.01:
		flat_dir = flat_dir.normalized()
		var turn_amount: float = clamp(_prev_flat_dir.cross(flat_dir).y * 14.0, -1.0, 1.0)
		_roll = lerp(_roll, turn_amount * max_bank_angle, 6.0 * delta)
		_prev_flat_dir = flat_dir
	target_basis = target_basis.rotated(face_dir, _roll)

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
