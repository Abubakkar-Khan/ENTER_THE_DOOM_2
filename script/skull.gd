extends CharacterBody3D
## Skull — one segment of the flock/dragon.
## CALM: true boid behavior (cohesion + alignment + separation) layered on
##   top of a loose, noise-driven personal orbit — nothing is a fixed sine
##   ring anymore, so no two loops ever look the same and the flock reacts
##   to itself instead of tracing a carousel path.
## WARNING: the whole flock rushes — extremely fast — into a formation
##   shape around the leader, at a set distance out in front of the
##   player, gathering into a wing-like shape before it commits.
## ATTACK: trails the leader's recent path like a segment of a serpent's
##   body (see Spawner.get_history_position()), with a per-skull sideways
##   ripple so the chain slithers instead of tracing one exact line.
## After an ATTACK ends: scatters outward briefly, then drifts back into
##   its calm orbit on its own.

signal exploded(position: Vector3)

@export var health: float = 1.0
@export var attack_range: float = 4.0
@export var explosion_radius: float = 4.0
@export var explosion_damage: float = 15.0

@export var calm_speed: float = 16.0
@export var warning_speed: float = 78.0     # extremely fast formation rush-in
@export var attack_speed: float = 24.0
@export var recover_speed: float = 30.0
@export var turn_speed: float = 5.0
@export var max_bank_angle: float = 0.9    # radians — how far it leans into turns

@export var model_forward_correction: float = 0.0

@export var separation_radius: float = 2.2
@export var separation_strength: float = 9.0
@export var neighbor_radius: float = 12.0   # how far a skull "sees" flockmates
@export var cohesion_strength: float = 2.5
@export var alignment_strength: float = 1.8

@export var chain_wave_amplitude: float = 1.3  # sideways ripple while trailing in ATTACK

@export var recover_duration: float = 1.6  # scatter time right after an attack pass

const GOLDEN_ANGLE: float = 2.39996323

enum Phase { CALM, WARNING, ATTACK }   # must mirror Spawner.Phase (same order = same ints)
enum State { NORMAL, EXPLODING }

var state: State = State.NORMAL
var spawner: Node = null
var player: Node3D = null
var slot_index: int = -1
var chain_gap_frames: int = 5

# Per-skull calm-orbit personality, derived once from slot_index. Radius/
# speed/phase still vary skull-to-skull, but the motion itself is now
# noise-driven rather than pure sine, so it never repeats exactly.
var _ring_radius: float
var _ring_speed: float
var _ring_phase: float
var _altitude_amp: float
var _altitude_speed: float
var _altitude_phase: float
var _calm_time: float = 0.0

# Per-skull noise generator + individual variance, so 18 skulls don't read
# as 18 copies of the same script running with a phase offset.
var _noise: FastNoiseLite
var _speed_noise_offset: float
var _turn_speed_indiv: float
var _max_bank_indiv: float

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
	# Guarantees _noise and the rest of the per-skull personality exist even
	# if initialize() hasn't run yet (or never runs, e.g. a Skull placed
	# directly in a test scene) — _physics_process can otherwise fire
	# before the Spawner gets a chance to call initialize().
	if _noise == null:
		_init_personality()

## Called once by the Spawner right after instancing.
func initialize(swarm_spawner: Node, swarm_player: Node3D, slot: int, gap_frames: int) -> void:
	spawner = swarm_spawner
	player = swarm_player
	slot_index = slot
	chain_gap_frames = gap_frames
	_init_personality()

func _init_personality() -> void:
	var s: float = float(slot_index)
	_ring_radius = 9.0 + fmod(s * 3.3, 9.0)          # ~9..18
	_ring_speed = 0.18 + fmod(s * 0.081, 0.22)        # ~0.18..0.40
	_ring_phase = s * GOLDEN_ANGLE
	_altitude_amp = 2.0 + fmod(s * 1.7, 3.5)          # ~2..5.5
	_altitude_speed = 0.3 + fmod(s * 0.061, 0.35)
	_altitude_phase = s * GOLDEN_ANGLE * 1.5

	# Deterministic-but-unique seed per skull — same skull always moves the
	# same way across a run, but no two skulls share a noise field.
	_noise = FastNoiseLite.new()
	_noise.seed = slot_index * 977 + 13
	_noise.frequency = 1.0

	_speed_noise_offset = s * GOLDEN_ANGLE * 3.0
	_turn_speed_indiv = turn_speed * (0.85 + fmod(s * 0.257, 0.3))
	_max_bank_indiv = max_bank_angle * (0.8 + fmod(s * 0.199, 0.4))

func _physics_process(delta: float) -> void:
	if state == State.EXPLODING:
		return
	if player == null:
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return
	if global_position.distance_to(player.global_position) <= attack_range:
		print("touch check RANDOM player")
		_touch_player()
		explode()
		return
	_calm_time += delta
	_track_phase_change(delta)
	var target: Vector3 = _current_target()
	var speed: float = _current_speed()
	var steer: Vector3 = (target - global_position).normalized() * speed
	steer += _flock_forces()
	velocity = velocity.lerp(steer, _turn_speed_indiv * delta)
	move_and_slide()
	for i in range(get_slide_collision_count()):
		if get_slide_collision(i).get_collider() == player:
			_touch_player()
			explode()
			return
	_update_rotation(delta)

func _touch_player() -> void:
	if player.has_method("take_damage"):
		player.take_damage(10.0)
	elif player.has_method("apply_damage"):
		player.apply_damage(10.0)
		
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

	if spawner.phase == Phase.WARNING:
		# Rush into a formation slot around the leader, at a set distance
		# out from the player — this is the "gather up fast" moment.
		return spawner.leader_pos + spawner.get_formation_offset(slot_index)

	# ATTACK: trail the leader like a segment of its body, with a sideways
	# ripple so the chain slithers instead of tracing one exact line.
	var delay_frames: int = slot_index * chain_gap_frames
	var base_pos: Vector3 = spawner.get_history_position(delay_frames)
	var ahead_pos: Vector3 = spawner.get_history_position(max(delay_frames - 1, 0))
	var travel_dir: Vector3 = ahead_pos - base_pos
	if travel_dir.length() > 0.01:
		var side: Vector3 = travel_dir.normalized().cross(Vector3.UP)
		var wave: float = _noise.get_noise_1d(_calm_time * 3.0)
		return base_pos + side * wave * chain_wave_amplitude
	return base_pos

func _calm_target() -> Vector3:
	var angle: float = _calm_time * _ring_speed + _ring_phase
	# Slow noise-driven wobble on the angle and a breathing radius — the
	# ring is no longer a fixed carousel track, it drifts and never
	# retraces itself exactly.
	var wobble: float = _noise.get_noise_1d(_calm_time * 0.15) * 0.6
	var radius: float = _ring_radius * (1.0 + _noise.get_noise_1d(_calm_time * 0.08 + 50.0) * 0.35)
	var altitude: float = sin(_calm_time * _altitude_speed + _altitude_phase) * _altitude_amp \
		+ _noise.get_noise_1d(_calm_time * 0.2 + 100.0) * _altitude_amp * 0.5
	return spawner.leader_pos + Vector3(
		cos(angle + wobble) * radius,
		altitude,
		sin(angle + wobble) * radius
	)

func _current_speed() -> float:
	if _recover_timer > 0.0:
		return recover_speed

	var base_speed: float = calm_speed
	if spawner != null:
		if spawner.phase == Phase.WARNING:
			base_speed = warning_speed
		elif spawner.phase == Phase.ATTACK:
			base_speed = attack_speed

	# Per-skull speed flutter — reads like wingbeats instead of a constant
	# glide, and each skull flutters on its own unsynced clock.
	var flutter: float = _noise.get_noise_1d(_calm_time * 2.0 + _speed_noise_offset) * 0.18
	return base_speed * (1.0 + flutter)

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

	# Cohesion/alignment only really drive things in CALM. During
	# WARNING/ATTACK the formation offsets and chain-follow already give
	# structure — full boid pull there would fight the snap into shape.
	if neighbor_count > 0 and (spawner == null or spawner.phase == Phase.CALM):
		var to_center: Vector3 = (cohesion_sum / neighbor_count) - global_position
		if to_center.length() > 0.01:
			force += to_center.normalized() * cohesion_strength
		var avg_vel: Vector3 = alignment_sum / neighbor_count
		if avg_vel.length() > 0.01:
			force += avg_vel.normalized() * alignment_strength

	return force

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
		_roll = lerp(_roll, turn_amount * _max_bank_indiv, 6.0 * delta)
		_prev_flat_dir = flat_dir
	target_basis = target_basis.rotated(face_dir, _roll)

	transform.basis = transform.basis.slerp(target_basis, _turn_speed_indiv * delta)

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
