extends Node3D
## Spawner — the "dragon's mind"
## Owns the leader path (the head of the flock), the phase state machine,
## and a short rolling history of the leader's recent positions so skulls
## can trail behind it like segments of a serpent's body. Skulls read
## leader_pos / phase / history off this node every frame — nothing is
## pushed into them.

@export var skull_scene: PackedScene
@export var max_skulls: int = 18
@export var player: Node3D
@export var spawn_interval: float = 1.6    # new skull joins roughly this often, only during CALM

# ─── Dragon chain ───
# Each skull trails the one before it by this many physics frames. This is
# what gives the flock a sinuous, serpent-like body once it gathers/attacks.
@export var chain_gap_frames: int = 5

# ─── Calm phase: organic wandering ───
@export var calm_wander_speed: float = 9.0
@export var calm_wander_scale: float = 24.0
@export var calm_duration_min: float = 8.0
@export var calm_duration_max: float = 13.0

# ─── Warning phase: rapid gather + hold ───
@export var warning_duration: float = 1.4

# ─── Attack phase: one fast committed pass ───
@export var attack_duration: float = 2.2

enum Phase { CALM, WARNING, ATTACK }
enum AttackType { SWEEP, DIVE }

var phase: Phase = Phase.CALM
var leader_pos: Vector3 = Vector3.ZERO

var _phase_timer: float = 0.0
var _calm_duration: float = 10.0
var _time: float = 0.0

var _attack_type: AttackType = AttackType.SWEEP
var _attack_start: Vector3 = Vector3.ZERO
var _attack_end: Vector3 = Vector3.ZERO
var _attack_phase: float = 0.0

var _warning_point: Vector3 = Vector3.ZERO

# Ring buffer of leader positions, for the chain-follow effect.
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
			_update_attack(delta)

	_record_history()

	if phase == Phase.CALM:
		_update_spawning(delta)

# ─── CALM: layered sine wander, feels organic rather than mechanical ───

func _update_calm(delta: float) -> void:
	var p: Vector3 = player.global_position
	leader_pos = p + Vector3(
		sin(_time * 0.35) * calm_wander_scale + sin(_time * 0.9) * 4.0,
		14.0 + sin(_time * 0.5) * 5.0 + cos(_time * 1.3) * 1.5,
		cos(_time * 0.28) * calm_wander_scale + cos(_time * 0.8) * 3.0
	)

	_phase_timer += delta
	if _phase_timer >= _calm_duration:
		_begin_warning()

func _begin_warning() -> void:
	phase = Phase.WARNING
	_phase_timer = 0.0
	_warning_point = player.global_position + Vector3(0.0, 13.0, -14.0)
	# Hook a warning roar/sound here, e.g.: $WarningSound.play()

# ─── WARNING: leader holds nearly still, so the trailing chain naturally
#     bunches up tight behind it — no separate "compression" logic needed.

func _update_warning(delta: float) -> void:
	leader_pos = leader_pos.lerp(_warning_point, 6.0 * delta)
	leader_pos.y += sin(_time * 6.0) * 0.05   # tiny idle bob, doesn't look frozen

	_phase_timer += delta
	if _phase_timer >= warning_duration:
		_begin_attack()

# ─── ATTACK: one fast, committed sweep or dive through the player ───

func _begin_attack() -> void:
	phase = Phase.ATTACK
	_phase_timer = 0.0
	_attack_phase = 0.0
	_attack_type = (randi() % AttackType.size()) as AttackType

	var p: Vector3 = player.global_position
	if _attack_type == AttackType.SWEEP:
		var side: float = 1.0 if randf() < 0.5 else -1.0
		_attack_start = p + Vector3(-side * 32.0, 9.0, -6.0)
		_attack_end = p + Vector3(side * 32.0, 9.0, -6.0)
	else:
		_attack_start = p + Vector3(0.0, 24.0, -28.0)
		_attack_end = p + Vector3(0.0, 4.0, 22.0)

	leader_pos = _attack_start

func _update_attack(delta: float) -> void:
	_attack_phase += delta / attack_duration
	var t: float = clamp(_attack_phase, 0.0, 1.0)
	var eased: float = t * t * (3.0 - 2.0 * t)
	leader_pos = _attack_start.lerp(_attack_end, eased)

	if _attack_phase >= 1.0:
		phase = Phase.CALM
		_phase_timer = 0.0
		_calm_duration = randf_range(calm_duration_min, calm_duration_max)

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
