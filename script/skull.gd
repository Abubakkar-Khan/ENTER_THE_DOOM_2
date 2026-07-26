extends CharacterBody3D
## Skull — one segment of the flock/dragon.
## CALM: true boid behavior (cohesion + alignment + separation) layered on
##   top of a loose, noise-driven personal orbit. Flock forces are
##   low-pass filtered before use — this is what kills the jitter, since
##   raw neighbor-based forces spike every time a nearby skull's position
##   or velocity changes.
## WARNING: the whole flock rushes into a wing-shaped formation around the
##   leader, oriented toward the player, out at a set distance.
## ATTACK: the leader runs a whole dive+climb campaign (see Spawner), and
##   each skull trails the leader's path *plus* a formation offset that's
##   oriented to the current flight direction — a wing spread, not a
##   single line. Skulls near the center of the wing pass through the
##   player and hit; skulls further out whoosh past by design.
## After a campaign ends: scatters outward briefly, then drifts back into
##   its calm orbit on its own.

signal exploded(position: Vector3)

@export var health: float = 1.0
@export var attack_range: float = 5
@export var touch_damage: float = 10.0
@export var explosion_radius: float = 2.0
@export var explosion_damage: float = 0.0   # touch already deals damage; splash is separate/optional

@export var calm_speed: float = 28.0
@export var warning_speed: float = 95.0      # extremely fast formation rush-in
@export var attack_speed: float = 155.0      # fast, committed strike
@export var recover_speed: float = 45.0

# Turn/bank response is phase-based: slow and graceful while wandering,
# still smooth but snappier while gathering/attacking.
@export var turn_speed_calm: float = 2.2
@export var turn_speed_attack: float = 7.5
@export var max_bank_calm: float = 0.9        # radians — wide, graceful lean while wandering
@export var max_bank_attack: float = 0.55     # radians — noticeable lean while attacking

@export var model_forward_correction: float = 0.0

@export var separation_radius: float = 2.2
@export var separation_strength: float = 7.0
@export var neighbor_radius: float = 12.0
@export var cohesion_strength: float = 1.8
@export var alignment_strength: float = 1.3

@export var recover_duration: float = 1.6

@export var scream_trigger_distance: float = 15.0
@export var scream_reset_distance: float = 24.0

@onready var scream: AudioStreamPlayer3D = get_node_or_null("scream")

const GOLDEN_ANGLE: float = 2.39996323

enum Phase { CALM, WARNING, ATTACK }   # must mirror Spawner.Phase (same order = same ints)
enum State { NORMAL, EXPLODING }

var state: State = State.NORMAL
var spawner: Node = null
var player: Node3D = null
var slot_index: int = -1
var chain_gap_frames: int = 5

var _ring_radius: float
var _ring_speed: float
var _ring_phase: float
var _altitude_amp: float
var _altitude_speed: float
var _altitude_phase: float
var _calm_time: float = 0.0

var _noise: FastNoiseLite
var _drift_offset: float
var _turn_indiv_factor: float
var _bank_indiv_factor: float
var _speed_indiv_factor: float

var _last_phase: int = -1
var _recover_timer: float = 0.0
var _scatter_target: Vector3 = Vector3.ZERO
var _has_screamed: bool = false

var _prev_flat_dir: Vector3 = Vector3.FORWARD
var _roll: float = 0.0
var _smoothed_flock: Vector3 = Vector3.ZERO

func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	add_to_group("flying_skulls")
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if _noise == null:
		_init_personality()

	var anim := get_node_or_null("AnimationPlayer")
	if anim and anim.has_animation("fly"):
		anim.play("fly")

## Called once by the Spawner right after instancing.
func initialize(swarm_spawner: Node, swarm_player: Node3D, slot: int, gap_frames: int) -> void:
	spawner = swarm_spawner
	player = swarm_player
	slot_index = slot
	chain_gap_frames = gap_frames
	_init_personality()

func _init_personality() -> void:
	var s: float = float(slot_index)
	_ring_radius = 9.0 + fmod(s * 3.3, 9.0)
	_ring_speed = 0.12 + fmod(s * 0.05, 0.12)
	_ring_phase = s * GOLDEN_ANGLE
	_altitude_amp = 2.0 + fmod(s * 1.7, 3.5)
	_altitude_speed = 0.22 + fmod(s * 0.045, 0.2)
	_altitude_phase = s * GOLDEN_ANGLE * 1.5

	_noise = FastNoiseLite.new()
	_noise.seed = slot_index * 977 + 13
	_noise.frequency = 1.0

	_drift_offset = s * GOLDEN_ANGLE * 3.0
	_turn_indiv_factor = 0.94 + fmod(s * 0.14, 0.12)
	_bank_indiv_factor = 0.92 + fmod(s * 0.11, 0.16)
	_speed_indiv_factor = 0.9 + fmod(s * 0.071, 0.22)

func _physics_process(delta: float) -> void:
	if state == State.EXPLODING:
		return

	if player == null:
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return

	_calm_time += delta
	_track_phase_change(delta)
	_update_scream()

	var target: Vector3 = _current_target()
	var speed: float = _current_speed()
	var turn_rate: float = _current_turn_rate()

	# Low-pass filter the flock forces so a neighbor suddenly entering or
	# leaving range doesn't yank the steering direction around every frame.
	var raw_flock: Vector3 = _flock_forces()
	_smoothed_flock = _smoothed_flock.lerp(raw_flock, 3.0 * delta)

	var steer: Vector3 = (target - global_position).normalized() * speed
	steer += _smoothed_flock

	velocity = velocity.lerp(steer, turn_rate * delta)

	var prev_pos: Vector3 = global_position
	move_and_slide()

	if _check_player_touch(prev_pos):
		return

	for i in range(get_slide_collision_count()):
		if get_slide_collision(i).get_collider() == player:
			_touch_player()
			explode()
			return

	_update_rotation(delta, turn_rate)

## Plays the scream once as a skull closes in on the player, then resets
## once it's flown back out past scream_reset_distance — so it fires again
## on the next approach (e.g. once per dive pass) instead of spamming.
func _update_scream() -> void:
	if scream == null or player == null:
		return
	var dist: float = global_position.distance_to(player.global_position)
	if dist < scream_trigger_distance and not _has_screamed:
		scream.play()
		_has_screamed = true
	elif dist > scream_reset_distance:
		_has_screamed = false

## Closest-point-on-segment check between last frame's position and this
## frame's, so a fast dive can't tunnel straight past the player without
## registering a hit.
func _check_player_touch(prev_pos: Vector3) -> bool:
	var seg: Vector3 = global_position - prev_pos
	var closest: Vector3
	if seg.length_squared() > 0.0001:
		var t: float = clamp((player.global_position - prev_pos).dot(seg) / seg.length_squared(), 0.0, 1.0)
		closest = prev_pos + seg * t
	else:
		closest = global_position

	if closest.distance_to(player.global_position) <= attack_range:
		_touch_player()
		explode()
		return true
	return false

func _touch_player() -> void:
	if player == null:
		return
	if player.has_method("take_damage"):
		player.take_damage(touch_damage)
	elif player.has_method("apply_damage"):
		player.apply_damage(touch_damage)

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

	var forward: Vector3 = spawner.get_leader_forward()

	if spawner.phase == Phase.WARNING:
		return spawner.leader_pos + spawner.get_formation_offset(slot_index, spawner.formation_radius, forward)

	# ATTACK: trail the leader's dive path like a segment of a serpent's
	# body, spread into a wing formation. Center-slot skulls pass through
	# the player and hit; outer ones whoosh past — some, not all, on purpose.
	var delay_frames: int = slot_index * chain_gap_frames
	var base_pos: Vector3 = spawner.get_history_position(delay_frames)
	return base_pos + spawner.get_formation_offset(slot_index, spawner.attack_formation_radius, forward)

func _calm_target() -> Vector3:
	var drift: float = 1.0 + _noise.get_noise_1d(_calm_time * 0.05 + _drift_offset) * 0.2
	var angle: float = _calm_time * _ring_speed * drift + _ring_phase
	var radius: float = _ring_radius * (1.0 + _noise.get_noise_1d(_calm_time * 0.04 + 50.0) * 0.12)
	var altitude: float = sin(_calm_time * _altitude_speed + _altitude_phase) * _altitude_amp
	return spawner.leader_pos + Vector3(
		cos(angle) * radius,
		altitude,
		sin(angle) * radius
	)

func _current_speed() -> float:
	var base: float
	if _recover_timer > 0.0:
		base = recover_speed
	elif spawner == null:
		base = calm_speed
	elif spawner.phase == Phase.WARNING:
		base = warning_speed
	elif spawner.phase == Phase.ATTACK:
		base = attack_speed
	else:
		base = calm_speed
	return base * _speed_indiv_factor

func _current_turn_rate() -> float:
	var base_turn: float = turn_speed_calm
	if _recover_timer > 0.0 or (spawner != null and spawner.phase != Phase.CALM):
		base_turn = turn_speed_attack
	return base_turn * _turn_indiv_factor

func _flock_forces() -> Vector3:
	var cohesion_sum: Vector3 = Vector3.ZERO
	var alignment_sum: Vector3 = Vector3.ZERO
	var separation_sum: Vector3 = Vector3.ZERO
	var neighbor_count: int = 0

	for other in get_tree().get_nodes_in_group("flying_skulls"):
		if other == self or not is_instance_valid(other):
			continue
		var to_other: Vector3 = other.global_position - global_position
		var dist: float = to_other.length()
		if dist <= 0.001:
			continue
		if dist < separation_radius:
			separation_sum += (-to_other / dist) * (separation_radius - dist)
		if dist < neighbor_radius:
			cohesion_sum += other.global_position
			alignment_sum += other.velocity
			neighbor_count += 1

	var force: Vector3 = separation_sum * separation_strength

	if neighbor_count > 0 and (spawner == null or spawner.phase == Phase.CALM):
		var to_center: Vector3 = (cohesion_sum / neighbor_count) - global_position
		if to_center.length() > 0.01:
			force += to_center.normalized() * cohesion_strength
		var avg_vel: Vector3 = alignment_sum / neighbor_count
		if avg_vel.length() > 0.01:
			force += avg_vel.normalized() * alignment_strength

	# Clamp so a sudden close encounter can't spike the steering direction.
	if force.length() > 10.0:
		force = force.normalized() * 10.0

	return force

func _update_rotation(delta: float, turn_rate: float) -> void:
	if velocity.length() <= 1.0:
		return

	var face_dir: Vector3 = velocity.normalized()
	var target_basis: Basis = Basis.looking_at(-face_dir, Vector3.UP)
	target_basis = target_basis.rotated(Vector3.UP, model_forward_correction)

	var bank_limit: float = max_bank_calm
	if _recover_timer > 0.0 or (spawner != null and spawner.phase != Phase.CALM):
		bank_limit = max_bank_attack
	bank_limit *= _bank_indiv_factor

	var flat_dir: Vector3 = Vector3(face_dir.x, 0.0, face_dir.z)
	if flat_dir.length() > 0.01 and _prev_flat_dir.length() > 0.01:
		flat_dir = flat_dir.normalized()
		var turn_amount: float = clamp(_prev_flat_dir.cross(flat_dir).y * 6.0, -1.0, 1.0)
		_roll = lerp(_roll, turn_amount * bank_limit, 4.0 * delta)
		_prev_flat_dir = flat_dir
	target_basis = target_basis.rotated(face_dir, _roll)

	transform.basis = transform.basis.slerp(target_basis, turn_rate * delta)

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

	if explosion_damage > 0.0 and player and global_position.distance_to(player.global_position) <= explosion_radius:
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
