extends Node3D
## Spawner — the "dragon's mind"
## Owns the leader path (the head of the flock), the phase state machine,
## and a short rolling history of the leader's recent positions so skulls
## can trail behind it like segments of a serpent's body. Skulls read
## leader_pos / phase / history / formation offsets off this node every
## frame — nothing is pushed into them.
##
## ATTACK is now a whole "campaign": the leader dives through/near the
## player, climbs back up high, circles to a new angle, and dives again —
## repeating for up to ~30 seconds before finally settling back to CALM.
## Each dive is one whoosh; the climbs in between are what make it read as
## a bird circling high up before swooping again, instead of one pass.

@export var skull_scene: PackedScene
@export var max_skulls: int = 18
@export var player: Node3D
@export var spawn_interval: float = 1.6    # new skull joins roughly this often, only during CALM

# ─── Dragon chain ───
@export var chain_gap_frames: int = 5

# ─── Calm phase: organic wandering ───
@export var calm_wander_speed: float = 0.12
@export var calm_wander_scale: float = 24.0
@export var calm_duration_min: float = 8.0
@export var calm_duration_max: float = 13.0

# ─── Warning phase: the flock rushes into formation ───
@export var warning_duration: float = 2.4
@export var formation_distance_from_player: float = 32.0
@export var formation_radius: float = 7.0
@export var formation_flatten: float = 0.55   # <1 flattens the sphere into a wing-like shape

# ─── Attack campaign: repeated dive + climb passes, up to ~30s ───
@export var attack_campaign_duration_min: float = 20.0
@export var attack_campaign_duration_max: float = 30.0
@export var pass_dive_duration: float = 3.0     # one whoosh through the player
@export var pass_climb_duration: float = 1.7      # climbing back up high between dives
@export var high_altitude: float = 42.0           # how high it circles between dives
@export var dive_curve_amount: float = 2.0       # bow on each dive's path (not a straight line)
@export var attack_formation_radius: float = 10.0  # wing-spread while diving — skulls near the
													 # center line hit the player, ones further
													 # out whoosh past. by design: some, not all.
@export var attack_homing: float = 1.6            # how strongly a dive corrects toward the player

enum Phase { CALM, WARNING, ATTACK }
enum AttackSub { DIVE, CLIMB }

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

var _noise: FastNoiseLite

var _history: Array[Vector3] = []
var _history_capacity: int = 0
var _history_write: int = 0

var slot_taken: Array[bool] = []
var _spawn_timer: float = 0.0

func _ready() -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player")

	var anchor: Vector3 = player.global_position if player else global_position
	leader_pos = anchor + Vector3(0, 15, -25)

	_history_capacity = max(max_skulls * chain_gap_frames + 60, 60)
	_history.resize(_history_capacity)
	_history.fill(leader_pos)

	_calm_duration = randf_range(calm_duration_min, calm_duration_max)

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

# ─── CALM: noise-driven wander, feels organic and never repeats ───

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
	var approach_dir: Vector3 = to_player.normalized() if to_player.length() > 0.5 else Vector3.BACK
	_warning_point = player.global_position - approach_dir * formation_distance_from_player + Vector3(0, 13, 0)

func _update_warning(delta: float) -> void:
	leader_pos = leader_pos.lerp(_warning_point, 10.0 * delta)
	leader_pos.y += sin(_time * 6.0) * 0.05

	_phase_timer += delta
	if _phase_timer >= warning_duration:
		_begin_attack_campaign()

## Deterministic per-slot offset used to spread skulls into a formation —
## used both for the WARNING gather-up (radius = formation_radius) and for
## the wing-spread while diving in ATTACK (radius = attack_formation_radius).
## Flattened fibonacci-sphere spread: evenly distributed, stable frame to
## frame, no jitter or overlap — reads as a deliberate wing, not a clump.
func get_formation_offset(slot: int, radius: float) -> Vector3:
	var n: float = float(max(max_skulls, 1))
	var i: float = float(slot) + 0.5
	var phi: float = acos(clamp(1.0 - 2.0 * i / n, -1.0, 1.0))
	var theta: float = PI * (1.0 + sqrt(5.0)) * i
	return Vector3(
		sin(phi) * cos(theta) * radius,
		cos(phi) * radius * formation_flatten,
		sin(phi) * sin(theta) * radius
	)

# ─── ATTACK CAMPAIGN: repeated dive + climb passes — "wosh and wosh" — for
#     up to ~30 seconds before finally breaking off back to CALM. ───

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
	var p: Vector3 = player.global_position
	var side: float = 1.0 if randf() < 0.5 else -1.0
	# Aim just past the player so the dive carries all the way through
	# instead of stopping dead on top of them.
	
	# Fly THROUGH the player instead of beside them.
	var attack_dir = (_dive_start - player.global_position).normalized()

	# Fly THROUGH the player's chest, then continue 35m forward.
	var player_target = player.global_position + Vector3(0, 1.5, 0)
	_dive_end = player_target + attack_dir * 35.0

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
	var attack_dir = (_dive_start - player.global_position).normalized()
	var desired_end = player.global_position - attack_dir * 30.0

	_dive_end = _dive_end.lerp(desired_end, attack_homing * delta)

	var mid = (_dive_start + _dive_end) * 0.5
	mid.y -= 2.0          # slight dip only
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
	# Circle up high and off to a new angle before the next dive — the
	# "flies high up, then comes back down" beat.
	var angle: float = randf_range(0.0, TAU)
	var radius: float = randf_range(20.0, 38.0)
	_climb_end = player.global_position + Vector3(cos(angle) * radius, high_altitude, sin(angle) * radius)

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
## Skulls use this to trail the leader like segments of a body.
func get_history_position(delay_frames: int) -> Vector3:
	var clamped_delay: int = clamp(delay_frames, 0, _history_capacity - 1)
	var idx: int = (_history_write - 1 - clamped_delay) % _history_capacity
	if idx < 0:
		idx += _history_capacity
	return _history[idx]

# ─── Spawning ───

func _update_spawning(delta: float) -> void:
	_spawn_timer += delta
	if _spawn_timer < spawn_interval:
		return
	_spawn_timer = 0.0

	var slot: int = slot_taken.find(false)
	if slot == -1:
		return
	_spawn_skull(slot)

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
