extends Node3D
## Spawner — the "dragon's mind"
## Owns the leader path (the head of the flock), the phase state machine,
## a short rolling history of the leader's recent positions (chain-follow),
## and formation offsets. Skulls read leader_pos / phase / history /
## formation offsets off this node every frame — nothing is pushed into
## them.
##
## ATTACK is a whole "campaign": the leader dives through/near the player,
## climbs back up high, circles to a new angle (left/right/high/rear/low),
## and dives again — repeating for up to ~30 seconds before settling back
## to CALM. Each dive overshoots well past the player so it reads as a
## long sweeping pass, not a stab.

@export var skull_scene: PackedScene
@export var max_skulls: int = 18
@export var player: Node3D
@export var chain_gap_frames: int = 5

# ─── Wave spawning — groups arrive together, staggered, not a trickle ───
@export var wave_min_size: int = 8
@export var wave_max_size: int = 18
@export var wave_interval_min: float = 5.0
@export var wave_interval_max: float = 8.0
@export var wave_spawn_stagger: float = 0.25   # seconds between individual spawns within a wave

# ─── Calm phase: organic wandering, never stops ───
@export var calm_wander_speed: float = 1.12
@export var calm_wander_scale: float = 30.0
@export var calm_duration_min: float = 2.0
@export var calm_duration_max: float = 5.0

# ─── Warning phase: the flock rushes into formation ───
@export var warning_duration: float = 2.4
@export var formation_distance_from_player: float = 35.0
@export var formation_radius: float = 10.0
@export var formation_flatten: float = 0.5   # <1 flattens into a wing shape

# ─── Attack campaign: repeated dive + climb passes, up to ~30s ───
@export var attack_campaign_duration_min: float = 20.0
@export var attack_campaign_duration_max: float = 30.0
@export var pass_dive_duration: float = 3.6      # one long sweeping whoosh through the player
@export var pass_climb_duration: float = 2.4     # climbing back up high between dives
@export var high_altitude: float = 46.0
@export var dive_curve_amount: float = 5.0       # bigger bow = a real arc, not a straight stab
@export var dive_overshoot_min: float = 40.0     # how far it keeps flying PAST the player
@export var dive_overshoot_max: float = 75.0
@export var attack_formation_radius: float = 14.0  # wing-spread while diving — center skulls fly
													 # closest to the player, outer ones pass wide
@export var attack_homing: float = 1.6

enum Phase { CALM, WARNING, ATTACK }
enum AttackSub { DIVE, CLIMB }
enum ApproachType { LEFT, RIGHT, HIGH, REAR, LOW }

var phase: Phase = Phase.CALM
var leader_pos: Vector3 = Vector3.ZERO

var _phase_timer: float = 0.0
var _calm_duration: float = 10.0
var _time: float = 0.0

var _attack_sub: AttackSub = AttackSub.DIVE
var _campaign_timer: float = 0.0
var _campaign_duration: float = 24.0
var _sub_timer: float = 0.0

var _dive_start: Vector3 = Vector3.ZERO
var _dive_end: Vector3 = Vector3.ZERO
var _dive_mid_offset: Vector3 = Vector3.ZERO
var _climb_start: Vector3 = Vector3.ZERO
var _climb_end: Vector3 = Vector3.ZERO

var _warning_point: Vector3 = Vector3.ZERO
var _approach_dir: Vector3 = Vector3.BACK

var _noise: FastNoiseLite

var _history: Array[Vector3] = []
var _history_capacity: int = 0
var _history_write: int = 0

var slot_taken: Array[bool] = []
var _wave_timer: float = 0.0
var _next_wave_interval: float = 8.0
var _pending_spawns: int = 0
var _spawn_stagger_timer: float = 0.0

func _ready() -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player")

	var anchor: Vector3 = player.global_position if player else global_position
	leader_pos = anchor + Vector3(0, 15, -25)

	_history_capacity = max(max_skulls * chain_gap_frames + 60, 60)
	_history.resize(_history_capacity)
	_history.fill(leader_pos)

	_calm_duration = randf_range(calm_duration_min, calm_duration_max)
	_next_wave_interval = randf_range(wave_interval_min, wave_interval_max)

	_noise = FastNoiseLite.new()
	_noise.seed = randi()
	_noise.frequency = 1.0

	slot_taken.resize(max_skulls)
	slot_taken.fill(false)

func _physics_process(delta: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return

	_time += delta

	match phase:
		Phase.CALM:
			_update_calm(delta)
		Phase.WARNING:
			_update_warning(delta)
		Phase.ATTACK:
			_update_attack_campaign(delta)

	_record_history()

	if phase == Phase.CALM:
		_update_spawning(delta)

# ─── CALM: noise-driven wander — organic, never repeats, never stops ───

func _update_calm(delta: float) -> void:
	var p: Vector3 = player.global_position
	var t: float = _time * calm_wander_speed
	leader_pos = p + Vector3(
		_noise.get_noise_2d(t, 0.0) * calm_wander_scale,
		14.0 + _noise.get_noise_2d(t, 100.0) * 5.0,
		_noise.get_noise_2d(t, 200.0) * calm_wander_scale
	)

	_phase_timer += delta
	if _phase_timer >= _calm_duration:
		_begin_warning()

func _begin_warning() -> void:
	phase = Phase.WARNING
	_phase_timer = 0.0
	var to_player: Vector3 = (player.global_position - leader_pos)
	to_player.y = 0.0
	_approach_dir = to_player.normalized() if to_player.length() > 0.5 else Vector3.BACK
	_warning_point = player.global_position - _approach_dir * formation_distance_from_player + Vector3(0, 13, 0)

func _update_warning(delta: float) -> void:
	leader_pos = leader_pos.lerp(_warning_point, 10.0 * delta)
	leader_pos.y += sin(_time * 6.0) * 0.05

	_phase_timer += delta
	if _phase_timer >= warning_duration:
		_begin_attack_campaign()

## Deterministic per-slot offset that spreads skulls into a wing shape,
## oriented perpendicular to whatever direction the leader is currently
## flying. Radius grows with sqrt(slot/total): low slots sit near the
## center of the wing (closest to the player's flight line), high slots
## sit further out (they whoosh past wide). That's what makes it read as
## a deliberate formation instead of a clump or a single line.
func get_formation_offset(slot: int, radius: float, forward: Vector3 = Vector3.FORWARD) -> Vector3:
	var n: float = float(max(max_skulls, 1))
	var i: float = float(slot) + 0.5
	var r: float = radius * sqrt(i / n)
	var theta: float = PI * (1.0 + sqrt(5.0)) * i

	var fwd: Vector3 = forward
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var right: Vector3 = fwd.cross(Vector3.UP)
	if right.length() < 0.01:
		right = Vector3.RIGHT
	right = right.normalized()
	var up: Vector3 = right.cross(fwd).normalized()

	return right * (cos(theta) * r) + up * (sin(theta) * r * formation_flatten)

## The direction the leader is currently flying, used to orient the wing
## formation so it faces the direction of travel.
func get_leader_forward() -> Vector3:
	if phase == Phase.WARNING:
		return _approach_dir
	if phase == Phase.ATTACK:
		if _attack_sub == AttackSub.DIVE:
			var d: Vector3 = _dive_end - _dive_start
			return d.normalized() if d.length() > 0.01 else Vector3.FORWARD
		else:
			var d2: Vector3 = _climb_end - _climb_start
			return d2.normalized() if d2.length() > 0.01 else Vector3.FORWARD
	return Vector3.FORWARD

# ─── ATTACK CAMPAIGN: repeated dive + climb passes for up to ~30 seconds
#     before finally breaking off back to CALM. ───

func _begin_attack_campaign() -> void:
	phase = Phase.ATTACK
	_phase_timer = 0.0
	_campaign_timer = 0.0
	_campaign_duration = randf_range(attack_campaign_duration_min, attack_campaign_duration_max)
	_begin_dive_pass()

func _update_attack_campaign(delta: float) -> void:
	_campaign_timer += delta
	match _attack_sub:
		AttackSub.DIVE:
			_update_dive_pass(delta)
		AttackSub.CLIMB:
			_update_climb_pass(delta)

func _begin_dive_pass() -> void:
	_attack_sub = AttackSub.DIVE
	_sub_timer = 0.0

	_dive_start = leader_pos
	var attack_dir: Vector3 = (_dive_start - player.global_position).normalized()
	var player_target: Vector3 = player.global_position + Vector3(0, 1.5, 0)
	var overshoot: float = randf_range(dive_overshoot_min, dive_overshoot_max)
	_dive_end = player_target + attack_dir * overshoot

	_dive_mid_offset = Vector3(
		randf_range(-dive_curve_amount, dive_curve_amount),
		randf_range(-dive_curve_amount * 0.3, dive_curve_amount * 0.3),
		randf_range(-dive_curve_amount, dive_curve_amount)
	)

func _update_dive_pass(delta: float) -> void:
	_sub_timer += delta
	var t: float = clamp(_sub_timer / pass_dive_duration, 0.0, 1.0)
	var eased: float = t * t * (3.0 - 2.0 * t)

	# Gentle homing — keeps the dive credible if the player moves, without
	# turning it into an aimbot lock.
	var attack_dir: Vector3 = (_dive_start - player.global_position).normalized()
	var desired_end: Vector3 = player.global_position - attack_dir * 30.0
	_dive_end = _dive_end.lerp(desired_end, attack_homing * delta)

	var mid: Vector3 = (_dive_start + _dive_end) * 0.5
	mid.y -= 2.0
	mid += _dive_mid_offset
	leader_pos = _quad_bezier(_dive_start, mid, _dive_end, eased)

	if t >= 1.0:
		if _campaign_timer >= _campaign_duration:
			_end_attack_campaign()
		else:
			_begin_climb_pass()

func _begin_climb_pass() -> void:
	_attack_sub = AttackSub.CLIMB
	_sub_timer = 0.0
	_climb_start = leader_pos

	# Vary WHERE the next dive comes from — left/right sweep, a steep high
	# dive, a rear attack, or a low skim — so attacks don't all look alike.
	var approach: ApproachType = (randi() % ApproachType.size()) as ApproachType
	var base_angle: float = _angle_to_player()
	var angle: float = base_angle
	var altitude: float = high_altitude
	var radius: float = randf_range(24.0, 42.0)

	match approach:
		ApproachType.LEFT:
			angle = base_angle + PI * 0.5 + randf_range(-0.3, 0.3)
			altitude = randf_range(26.0, 38.0)
		ApproachType.RIGHT:
			angle = base_angle - PI * 0.5 + randf_range(-0.3, 0.3)
			altitude = randf_range(26.0, 38.0)
		ApproachType.HIGH:
			angle = randf_range(0.0, TAU)
			altitude = randf_range(high_altitude, high_altitude + 20.0)
			radius = randf_range(14.0, 24.0)
		ApproachType.REAR:
			angle = base_angle + PI + randf_range(-0.3, 0.3)
			altitude = randf_range(20.0, 32.0)
		ApproachType.LOW:
			angle = randf_range(0.0, TAU)
			altitude = randf_range(6.0, 12.0)
			radius = randf_range(30.0, 46.0)

	_climb_end = player.global_position + Vector3(cos(angle) * radius, altitude, sin(angle) * radius)

func _angle_to_player() -> float:
	var d: Vector3 = leader_pos - player.global_position
	return atan2(d.z, d.x)

func _update_climb_pass(delta: float) -> void:
	_sub_timer += delta
	var t: float = clamp(_sub_timer / pass_climb_duration, 0.0, 1.0)
	var eased: float = t * t * (3.0 - 2.0 * t)
	leader_pos = _climb_start.lerp(_climb_end, eased)

	if t >= 1.0:
		_begin_dive_pass()

func _end_attack_campaign() -> void:
	phase = Phase.CALM
	_phase_timer = 0.0
	_calm_duration = randf_range(calm_duration_min, calm_duration_max)

func _quad_bezier(a: Vector3, b: Vector3, c: Vector3, t: float) -> Vector3:
	return a.lerp(b, t).lerp(b.lerp(c, t), t)

# ─── History ring buffer ───

func _record_history() -> void:
	_history[_history_write] = leader_pos
	_history_write = (_history_write + 1) % _history_capacity

## Returns the leader's position from `delay_frames` physics steps ago.
func get_history_position(delay_frames: int) -> Vector3:
	var clamped_delay: int = clamp(delay_frames, 0, _history_capacity - 1)
	var idx: int = (_history_write - 1 - clamped_delay) % _history_capacity
	if idx < 0:
		idx += _history_capacity
	return _history[idx]

# ─── Wave spawning ───

func _update_spawning(delta: float) -> void:
	if _pending_spawns > 0:
		_spawn_stagger_timer += delta
		if _spawn_stagger_timer >= wave_spawn_stagger:
			_spawn_stagger_timer = 0.0
			_try_spawn_one()
		return

	_wave_timer += delta
	if _wave_timer < _next_wave_interval:
		return
	_wave_timer = 0.0
	_next_wave_interval = randf_range(wave_interval_min, wave_interval_max)

	var free_slots: int = 0
	for taken in slot_taken:
		if not taken:
			free_slots += 1
	if free_slots > 0:
		_pending_spawns = min(randi_range(wave_min_size, wave_max_size), free_slots)

func _try_spawn_one() -> void:
	var slot: int = slot_taken.find(false)
	if slot == -1:
		_pending_spawns = 0
		return
	_spawn_skull(slot)
	_pending_spawns -= 1

func _spawn_skull(slot: int) -> void:
	if skull_scene == null:
		return

	slot_taken[slot] = true

	var skull := skull_scene.instantiate()
	skull.global_position = global_position
	get_tree().current_scene.add_child(skull)

	if skull.has_method("initialize"):
		skull.initialize(self, player, slot, chain_gap_frames)

func notify_skull_died(slot: int) -> void:
	if slot >= 0 and slot < slot_taken.size():
		slot_taken[slot] = false
