extends Node3D
## Spawner — the "dragon's mind"
## Owns the leader path (the head of the flock), the phase state machine,
## a short rolling history of the leader's recent positions (chain-follow),
## and formation offsets. Skulls read leader_pos / phase / history /
## formation offsets off this node every frame — nothing is pushed into
## them.
##
## ATTACK is a whole "campaign": the leader dives through/near the player,
## climbs back up in a decaying SPIRAL (not a straight elevator), circles
## to a new angle (left/right/high/rear/low), and dives again — repeating
## for up to ~30 seconds before settling back to CALM. Each dive overshoots
## well past the player so it reads as a long sweeping pass, not a stab.
##
## BREATHING: formation radius is never fixed. It oscillates between tight
## and wide via get_formation_radius()/get_attack_formation_radius(), with
## occasional outward "explode" pulses — the flock looks alive even when
## nothing else is changing.
##
## CONTINUOUS PRESSURE: CALM isn't a true rest state. The leader periodically
## feints closer to the player on a noise curve, and the time spent in CALM
## shrinks the longer the encounter runs, so the player is rarely fully safe.
##
## DYNAMIC LEADER: a small noise-driven jitter is layered onto leader_pos
## in WARNING/ATTACK so the path never reads as a perfectly smooth spline.

@export var skull_scene: PackedScene
@export var max_skulls: int = 30          # the "flock" — wing formation, dive campaigns
@export var player: Node3D
@export var chain_gap_frames: int = 5

# ─── Wave spawning — a wave "portal" opens and releases several bursts
#     with a beat between each, then closes, instead of one steady trickle ───
@export var wave_min_size: int = 6
@export var wave_max_size: int = 15
@export var wave_interval_min: float = 5.0
@export var wave_interval_max: float = 8.0
@export var wave_spawn_stagger: float = 0.25   # seconds between individual spawns within a burst
@export var wave_burst_min: int = 3            # skulls per burst
@export var wave_burst_max: int = 6
@export var wave_burst_pause: float = 0.7      # pause between bursts within a wave

# ─── Solo skulls — a second population (~15) that ignores the flock/
#     dragon entirely. Each spawns FAR out in a random direction around
#     the player, flies straight in so it can be seen and tracked coming,
#     makes one committed strike pass, then peels off far away again and
#     loops. These run all the time, independent of CALM/WARNING/ATTACK. ───
@export var solo_max: int = 15
@export var solo_spawn_distance_min: float = 90.0
@export var solo_spawn_distance_max: float = 160.0
@export var solo_trickle_interval_min: float = 1.0
@export var solo_trickle_interval_max: float = 3.0
@export var solo_approach_speed: float = 42.0
@export var solo_strike_speed: float = 150.0
@export var solo_retreat_speed: float = 70.0
@export var solo_strike_trigger_distance: float = 55.0
@export var solo_overshoot_min: float = 20.0
@export var solo_overshoot_max: float = 45.0
@export var solo_retreat_distance_min: float = 100.0
@export var solo_retreat_distance_max: float = 170.0

# ─── Calm phase: organic wandering, never stops, never fully safe ───
@export var calm_wander_speed: float = 1.12
@export var calm_wander_scale: float = 30.0
@export var calm_duration_min: float = 2.0
@export var calm_duration_max: float = 5.0
@export var calm_feint_strength: float = 0.6   # how much a feint tightens the wander + drops altitude

# Continuous pressure: as the fight goes on, CALM windows shrink toward
# these floors so the player gets less and less of a breather.
@export var escalation_time: float = 90.0
@export var calm_duration_min_late: float = 0.8
@export var calm_duration_max_late: float = 1.8

# ─── Warning phase: the flock rushes into formation ───
@export var warning_duration: float = 2.4
@export var formation_distance_from_player: float = 35.0
@export var formation_radius: float = 10.0
@export var formation_flatten: float = 0.5   # <1 flattens into a wing shape

# ─── Flock breathing — formation radius pulses wide/tight over time, with
#     rare bigger "explode outward" pulses ───
@export var breath_min_scale: float = 0.55
@export var breath_max_scale: float = 1.35
@export var breath_speed: float = 0.18
@export var breath_pulse_chance_per_sec: float = 0.02
@export var breath_pulse_duration: float = 0.6

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

# Spiral recovery: the climb back to altitude bulges out into a decaying
# helix instead of a straight lerp — reads as a bird banking around, not
# an elevator.
@export var spiral_radius: float = 6.0
@export var spiral_turns: float = 1.5

@export var leader_jitter_amount: float = 0.6

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
var _climb_spiral_phase: float = 0.0

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
var _burst_queue: Array[int] = []
var _burst_pause_timer: float = 0.0

var solo_slot_taken: Array[bool] = []
var _solo_trickle_timer: float = 0.0
var _solo_next_trickle: float = 2.0

var _breath_pulse_timer: float = 0.0
var _breath_pulse_strength: float = 0.0

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

	solo_slot_taken.resize(solo_max)
	solo_slot_taken.fill(false)
	_solo_next_trickle = randf_range(solo_trickle_interval_min, solo_trickle_interval_max)

func _physics_process(delta: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return

	_time += delta
	_update_breathing(delta)

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

	_update_solo_spawning(delta)

# ─── Flock breathing ───

func _update_breathing(delta: float) -> void:
	if _breath_pulse_timer > 0.0:
		_breath_pulse_timer -= delta
	elif randf() < breath_pulse_chance_per_sec * delta:
		_breath_pulse_timer = breath_pulse_duration
		_breath_pulse_strength = randf_range(1.4, 1.9)

func get_formation_scale() -> float:
	var base: float = lerp(breath_min_scale, breath_max_scale, (sin(_time * breath_speed) + 1.0) * 0.5)
	if _breath_pulse_timer > 0.0:
		base = max(base, _breath_pulse_strength)
	return base

func get_formation_radius() -> float:
	return formation_radius * get_formation_scale()

func get_attack_formation_radius() -> float:
	return attack_formation_radius * get_formation_scale()

## Small noise-driven wobble layered onto leader_pos so the flight path
## never reads as a perfectly smooth spline.
func _leader_jitter(amplitude: float) -> Vector3:
	return Vector3(
		_noise.get_noise_1d(_time * 3.0 + 11.0),
		_noise.get_noise_1d(_time * 3.0 + 22.0) * 0.4,
		_noise.get_noise_1d(_time * 3.0 + 33.0)
	) * amplitude

## How far into the encounter we are, 0 → 1, used to shrink CALM windows
## over time so the flock keeps applying pressure as the fight goes on.
func _difficulty_t() -> float:
	return clamp(_time / max(escalation_time, 0.01), 0.0, 1.0)

# ─── CALM: noise-driven wander — organic, never repeats, occasionally
#     feints in closer so the player never fully relaxes ───

func _update_calm(delta: float) -> void:
	var p: Vector3 = player.global_position
	var t: float = _time * calm_wander_speed

	# Feint: a slow noise curve that occasionally pulls the wander tighter
	# and lower, reading as the flock "leaning in" before drifting back out.
	var feint: float = clamp(_noise.get_noise_2d(t * 0.3, 300.0) * 0.5 + 0.5, 0.0, 1.0)
	feint = pow(feint, 2.0)   # keep feints rare/short rather than half-time
	var wander_scale: float = calm_wander_scale * lerp(1.0, 1.0 - calm_feint_strength, feint)

	leader_pos = p + Vector3(
		_noise.get_noise_2d(t, 0.0) * wander_scale,
		14.0 + _noise.get_noise_2d(t, 100.0) * 5.0 - feint * calm_feint_strength * 6.0,
		_noise.get_noise_2d(t, 200.0) * wander_scale
	)
	leader_pos.y = max(leader_pos.y, player.global_position.y + 8.0)

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
	leader_pos += _leader_jitter(leader_jitter_amount)
	leader_pos.y = max(leader_pos.y, player.global_position.y + 8.0)

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

	# Never allow the dive to scrape the ground
	mid.y = max(mid.y, player.global_position.y + 5.0)

	mid += _dive_mid_offset

	leader_pos = _quad_bezier(_dive_start, mid, _dive_end, eased)
	leader_pos.y = max(leader_pos.y, player.global_position.y + 5.0)

	if t >= 1.0:
		if _campaign_timer >= _campaign_duration:
			_end_attack_campaign()
		else:
			_begin_climb_pass()

func _begin_climb_pass() -> void:
	_attack_sub = AttackSub.CLIMB
	_sub_timer = 0.0
	_climb_start = leader_pos
	_climb_spiral_phase = randf_range(0.0, TAU)

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

## Recovery isn't a straight elevator ride: a decaying helix is layered
## around the climb path, peaking mid-climb and settling to zero right as
## the leader arrives at the next approach point — reads as a banking
## spiral rather than a snap-to-altitude.
func _update_climb_pass(delta: float) -> void:
	_sub_timer += delta
	var t: float = clamp(_sub_timer / pass_climb_duration, 0.0, 1.0)
	var eased: float = t * t * (3.0 - 2.0 * t)
	var base_pos: Vector3 = _climb_start.lerp(_climb_end, eased)

	var fwd: Vector3 = (_climb_end - _climb_start)
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.UP
	var right: Vector3 = fwd.cross(Vector3.UP)
	if right.length() < 0.01:
		right = Vector3.RIGHT
	right = right.normalized()
	var up: Vector3 = right.cross(fwd).normalized()

	var spiral_amount: float = sin(t * PI)   # 0 at both ends, peaks mid-climb
	var angle: float = _climb_spiral_phase + t * spiral_turns * TAU
	var spiral_offset: Vector3 = (right * cos(angle) + up * sin(angle)) * spiral_radius * spiral_amount

	leader_pos = base_pos + spiral_offset + _leader_jitter(leader_jitter_amount)
	leader_pos.y = max(leader_pos.y, player.global_position.y + 5.0)

	if t >= 1.0:
		_begin_dive_pass()

func _end_attack_campaign() -> void:
	phase = Phase.CALM
	_phase_timer = 0.0

	# Continuous pressure: CALM windows shrink toward a floor as the
	# encounter runs longer, so breathers get shorter and shorter.
	var dt: float = _difficulty_t()
	var lo: float = lerp(calm_duration_min, calm_duration_min_late, dt)
	var hi: float = lerp(calm_duration_max, calm_duration_max_late, dt)
	_calm_duration = randf_range(lo, hi)

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

# ─── Wave spawning: a "portal" opens, releases several bursts back to
#     back with a short beat between each, then closes ───

func _update_spawning(delta: float) -> void:
	if _pending_spawns > 0:
		_spawn_stagger_timer += delta
		if _spawn_stagger_timer >= wave_spawn_stagger:
			_spawn_stagger_timer = 0.0
			_try_spawn_one()
		return

	if _burst_queue.size() > 0:
		_burst_pause_timer += delta
		if _burst_pause_timer >= wave_burst_pause:
			_burst_pause_timer = 0.0
			_pending_spawns = _burst_queue.pop_front()
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
	if free_slots <= 0:
		return

	var total: int = min(randi_range(wave_min_size, wave_max_size), free_slots)
	_burst_queue = _split_into_bursts(total)
	if _burst_queue.size() > 0:
		_pending_spawns = _burst_queue.pop_front()

## Splits a wave's total skull count into a few uneven bursts (e.g.
## 5 / 4 / 6) so a wave reads as "portal opens, several pulses, closes"
## instead of one long steady trickle.
func _split_into_bursts(total: int) -> Array[int]:
	var bursts: Array[int] = []
	var remaining: int = total
	while remaining > 0:
		var chunk: int = min(remaining, randi_range(wave_burst_min, wave_burst_max))
		bursts.append(chunk)
		remaining -= chunk
	return bursts

func _try_spawn_one() -> void:
	var slot: int = slot_taken.find(false)
	if slot == -1:
		_pending_spawns = 0
		_burst_queue.clear()
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

## Solo skulls trickle in continuously (independent of CALM/WARNING/ATTACK)
## up to solo_max at once, each spawned far out in a random direction so
## the player can see and track them closing in rather than having them
## pop in on top of them.
func _update_solo_spawning(delta: float) -> void:
	_solo_trickle_timer += delta
	if _solo_trickle_timer < _solo_next_trickle:
		return

	var slot: int = solo_slot_taken.find(false)
	if slot == -1:
		return

	_solo_trickle_timer = 0.0
	_solo_next_trickle = randf_range(solo_trickle_interval_min, solo_trickle_interval_max)
	_spawn_solo_skull(slot)

func _spawn_solo_skull(slot: int) -> void:
	if skull_scene == null:
		return

	solo_slot_taken[slot] = true

	var skull := skull_scene.instantiate()
	skull.global_position = random_far_point()
	get_tree().current_scene.add_child(skull)

	if skull.has_method("initialize_solo"):
		skull.initialize_solo(self, player, slot)

## A point far out from the player in a random compass direction and a
## modest random elevation — used both to spawn solo skulls and to send
## them somewhere far away again after a strike pass.
func random_far_point() -> Vector3:
	var dist: float = randf_range(solo_spawn_distance_min, solo_spawn_distance_max)
	var azimuth: float = randf_range(0.0, TAU)
	var elevation: float = randf_range(-0.1, 0.5)
	var horiz: float = cos(elevation)
	var dir: Vector3 = Vector3(cos(azimuth) * horiz, sin(elevation), sin(azimuth) * horiz)
	var base: Vector3 = (player.global_position if player else global_position) + Vector3(0, 10, 0)
	return base + dir * dist

func notify_skull_died(slot: int, is_solo: bool = false) -> void:
	if is_solo:
		if slot >= 0 and slot < solo_slot_taken.size():
			solo_slot_taken[slot] = false
	else:
		if slot >= 0 and slot < slot_taken.size():
			slot_taken[slot] = false
