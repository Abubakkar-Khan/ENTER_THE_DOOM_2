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
##   player and hit; skulls further out whoosh past by design, and some
##   are additionally nudged into a deliberate near-miss.
##
## MOMENTUM: steering no longer snaps velocity onto the target direction.
## Every frame we compute a desired velocity (direction * speed + flock
## force), turn that into an acceleration capped by _current_accel(), and
## integrate. A light drag term is applied after that so a skull carries
## momentum through a turn (wide arcs, overshoot, "never stops on a dime")
## instead of behaving like a drone locked to its target.
##
## After a campaign ends: scatters outward briefly, then drifts back into
##   its calm orbit on its own.

signal exploded(position: Vector3)

@export var health: float = 1.0
@export var attack_range: float = 5
@export var touch_damage: float = 2.0
@export var explosion_radius: float = 2.0
@export var explosion_damage: float = 0.0   # touch already deals damage; splash is separate/optional

@export var calm_speed: float = 28.0
@export var warning_speed: float = 95.0      # extremely fast formation rush-in
@export var attack_speed: float = 155.0      # fast, committed strike
@export var recover_speed: float = 45.0

# Momentum: acceleration is how hard the skull can push its velocity
# toward its desired velocity each second; drag is a light air-resistance
# term applied after that push. Low accel relative to speed = wide,
# heavy turns. Calm accel is soft (lazy wandering); attack accel is much
# harder (committed, but still not instant).
@export var accel_calm: float = 18.0
@export var accel_attack: float = 60.0
@export var drag: float = 1.6

# Speed isn't constant — it breathes between a low and high multiplier
# per-skull via noise, so the flock never reads as a fleet of identical
# drones moving at one speed. Attack phases get a bigger burst range.
@export var speed_burst_amount: float = 0.22
@export var speed_burst_attack_amount: float = 0.4
@export var speed_burst_freq: float = 0.55

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

# Some skulls are deliberately steered to whoosh past the player instead
# of connecting — scarier than a straight hit because it reads as an
# animal that could have killed you but chose not to (or almost didn't).
@export var near_miss_chance: float = 0.35
@export var near_miss_min: float = 0.5
@export var near_miss_max: float = 2.2

@export var scream_trigger_distance: float = 35.0
@export var scream_reset_distance: float = 80.0

# ─── Solo mode — an alternative to the flock/formation behavior above.
## A solo skull ignores the leader entirely. It's spawned far out by the
## Spawner (see initialize_solo), flies straight toward the player at a
## moderate, trackable speed, commits to one fast strike pass once close,
## then peels off far away again and repeats. Distances/speeds live on
## the Spawner (solo_* exports) so they're tuned in one place.

@onready var scream: AudioStreamPlayer3D = get_node_or_null("scream")
@onready var death_particles: CPUParticles3D = $death_particles
@onready var explosion_sound: AudioStreamPlayer2D = $explosion_sound

const GOLDEN_ANGLE: float = 2.39996323

enum Phase { CALM, WARNING, ATTACK }   # must mirror Spawner.Phase (same order = same ints)
enum State { NORMAL, EXPLODING }
enum SoloState { APPROACH, STRIKE, RETREAT }

var state: State = State.NORMAL
var spawner: Node = null
var player: Node3D = null
var slot_index: int = -1
var chain_gap_frames: int = 5

var is_solo: bool = false
var _solo_state: SoloState = SoloState.APPROACH
var _solo_target: Vector3 = Vector3.ZERO
var _solo_strike_target: Vector3 = Vector3.ZERO

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
var _near_miss_pick: float      # per-skull roll: whether/how far this slot near-misses
var _near_miss_side: float

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

	# Configure scream sound
	if scream:
		scream.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		scream.max_distance = 0.0    # 0 = no cutoff
		scream.volume_db = -3.0      # adjust to taste

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

## Called once by the Spawner for the independent "solo" pool instead of
## initialize(). These skulls never touch leader_pos/formation offsets —
## they run their own approach → strike → retreat loop.
func initialize_solo(swarm_spawner: Node, swarm_player: Node3D, slot: int) -> void:
	spawner = swarm_spawner
	player = swarm_player
	slot_index = slot
	is_solo = true
	_init_personality()
	_begin_solo_approach()

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

	_near_miss_pick = fmod(s * 0.6180339887, 1.0)     # golden-ratio hash, evenly spread in [0,1)
	_near_miss_side = 1.0 if (slot_index % 2 == 0) else -1.0

func _physics_process(delta: float) -> void:
	if state == State.EXPLODING:
		return

	if player == null:
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return

	_calm_time += delta
	if is_solo:
		_update_solo(delta)
	else:
		_track_phase_change(delta)
	_update_scream()

	var target: Vector3 = _current_target()
	var speed: float = _current_speed() * _speed_burst_multiplier()
	var accel: float = _current_accel()
	var turn_rate: float = _current_turn_rate()

	# Low-pass filter the flock forces so a neighbor suddenly entering or
	# leaving range doesn't yank the steering direction around every frame.
	var raw_flock: Vector3 = _flock_forces()
	_smoothed_flock = _smoothed_flock.lerp(raw_flock, 3.0 * delta)

	var to_target: Vector3 = target - global_position
	var desired_dir: Vector3
	if to_target.length() > 0.01:
		desired_dir = to_target.normalized()
	elif velocity.length() > 0.01:
		desired_dir = velocity.normalized()
	else:
		desired_dir = Vector3.FORWARD

	var desired_velocity: Vector3 = desired_dir * speed + _smoothed_flock

	# MOMENTUM: push velocity toward desired_velocity at a capped rate
	# (acceleration), then apply drag. This is what lets a skull carry
	# speed through a turn instead of snapping onto the new heading —
	# a dive keeps its speed past the player and swings back in a wide
	# arc rather than stopping and reversing on the spot.
	var accel_vec: Vector3 = desired_velocity - velocity
	var max_delta_v: float = accel * delta
	if accel_vec.length() > max_delta_v:
		accel_vec = accel_vec.normalized() * max_delta_v
	velocity += accel_vec
	velocity *= clamp(1.0 - drag * delta, 0.0, 1.0)

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

## Solo behavior: fly straight at the player from wherever it spawned
## (far away, so the approach is visible/trackable), commit to a fast
## overshooting strike once close, then peel off to a new far point and
## loop back into another approach.
func _update_solo(delta: float) -> void:
	if player == null or spawner == null:
		return

	match _solo_state:
		SoloState.APPROACH:
			_solo_target = player.global_position + Vector3(0, 3.0, 0)
			if global_position.distance_to(player.global_position) <= spawner.solo_strike_trigger_distance:
				_begin_solo_strike()
		SoloState.STRIKE:
			_solo_target = _solo_strike_target
			if global_position.distance_to(_solo_strike_target) < 6.0:
				_begin_solo_retreat()
		SoloState.RETREAT:
			if global_position.distance_to(_solo_target) < 10.0:
				_begin_solo_approach()

func _begin_solo_approach() -> void:
	_solo_state = SoloState.APPROACH
	_solo_target = player.global_position if player else global_position

func _begin_solo_strike() -> void:
	_solo_state = SoloState.STRIKE
	var dir: Vector3 = (player.global_position - global_position)
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	var overshoot: float = randf_range(spawner.solo_overshoot_min, spawner.solo_overshoot_max)
	_solo_strike_target = player.global_position + dir * overshoot + Vector3(0, randf_range(-2.0, 2.0), 0)
	_solo_target = _solo_strike_target

func _begin_solo_retreat() -> void:
	_solo_state = SoloState.RETREAT
	_solo_target = spawner.random_far_point()

func _current_target() -> Vector3:
	if is_solo:
		return _solo_target

	if spawner == null:
		return player.global_position

	if _recover_timer > 0.0:
		return _scatter_target

	if spawner.phase == Phase.CALM:
		return _calm_target()

	var forward: Vector3 = spawner.get_leader_forward()

	if spawner.phase == Phase.WARNING:
		return spawner.leader_pos + spawner.get_formation_offset(slot_index, spawner.get_formation_radius(), forward)

	# ATTACK: trail the leader's dive path like a segment of a serpent's
	# body, spread into a wing formation. Center-slot skulls pass through
	# the player and hit; outer ones whoosh past — and a subset get an
	# extra deliberate near-miss nudge, which reads scarier than a hit.
	var delay_frames: int = slot_index * chain_gap_frames
	var base_pos: Vector3 = spawner.get_history_position(delay_frames)
	var formation_offset: Vector3 = spawner.get_formation_offset(slot_index, spawner.get_attack_formation_radius(), forward)
	return base_pos + formation_offset + _near_miss_offset(forward)

## A small extra sideways nudge applied to some skulls during an attack
## pass so they visibly clear the player by a hair instead of connecting.
func _near_miss_offset(forward: Vector3) -> Vector3:
	if _near_miss_pick > near_miss_chance:
		return Vector3.ZERO

	var right: Vector3 = forward.cross(Vector3.UP)
	if right.length() < 0.01:
		right = Vector3.RIGHT
	right = right.normalized()

	var mag: float = lerp(near_miss_min, near_miss_max, _near_miss_pick / max(near_miss_chance, 0.001))
	return right * mag * _near_miss_side

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
	if is_solo:
		var solo_base: float = spawner.solo_approach_speed
		if _solo_state == SoloState.STRIKE:
			solo_base = spawner.solo_strike_speed
		elif _solo_state == SoloState.RETREAT:
			solo_base = spawner.solo_retreat_speed
		return solo_base * _speed_indiv_factor

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

## Per-skull speed noise so the flock doesn't move at one flat velocity —
## surges and lulls per individual, wider swings during an attack.
func _speed_burst_multiplier() -> float:
	var amp: float = speed_burst_amount
	if spawner != null and (spawner.phase == Phase.ATTACK or _recover_timer > 0.0):
		amp = speed_burst_attack_amount
	var n: float = _noise.get_noise_1d(_calm_time * speed_burst_freq + _drift_offset * 2.0 + 500.0)
	return 1.0 + n * amp

func _current_accel() -> float:
	if is_solo:
		return (accel_attack if _solo_state == SoloState.STRIKE else accel_calm) * _turn_indiv_factor

	var accel: float = accel_calm
	if _recover_timer > 0.0 or (spawner != null and spawner.phase != Phase.CALM):
		accel = accel_attack
	return accel * _turn_indiv_factor

func _current_turn_rate() -> float:
	if is_solo:
		return (turn_speed_attack if _solo_state == SoloState.STRIKE else turn_speed_calm) * _turn_indiv_factor

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
		if not is_solo and dist < neighbor_radius:
			cohesion_sum += other.global_position
			alignment_sum += other.velocity
			neighbor_count += 1

	var force: Vector3 = separation_sum * separation_strength

	if not is_solo and neighbor_count > 0 and (spawner == null or spawner.phase == Phase.CALM):
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
	if is_solo:
		if _solo_state == SoloState.STRIKE:
			bank_limit = max_bank_attack
	elif _recover_timer > 0.0 or (spawner != null and spawner.phase != Phase.CALM):
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

	# Notify spawner (which slot pool this belonged to matters — formation
	# vs. solo have separate slot arrays)
	if spawner and spawner.has_method("notify_skull_died"):
		spawner.notify_skull_died(slot_index, is_solo)

	# Award score
	if player and player.has_method("add_score"):
		player.add_score(10)

	# Explosion damage (if enabled)
	if explosion_damage > 0.0 and player and global_position.distance_to(player.global_position) <= explosion_radius:
		if player.has_method("take_damage"):
			player.take_damage(explosion_damage)
		elif player.has_method("apply_damage"):
			player.apply_damage(explosion_damage)

	# Hide meshes
	if has_node("Sketchfab_Scene"):
		$Sketchfab_Scene.visible = false
	if has_node("MeshInstance3D"):
		$MeshInstance3D.visible = false

	# Play death particles
	if death_particles and not death_particles.emitting:
		death_particles.emitting = true

	# Play explosion sound
	if explosion_sound and not explosion_sound.playing:
		explosion_sound.play()

	# Disable all collision shapes
	for shape in find_children("*", "CollisionShape3D"):
		shape.set_deferred("disabled", true)

	# Stop physics
	set_physics_process(false)
	emit_signal("exploded", global_position)

	# Wait then free
	await get_tree().create_timer(2.0).timeout
	queue_free()
