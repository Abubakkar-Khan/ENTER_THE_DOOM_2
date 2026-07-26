extends Node3D
## Spawner
## Spawns skulls gradually, replaces dead ones, and holds the few numbers
## the whole flock needs to move as one body (swarm_center, is_attacking,
## formation_compression). No moon, no telegraph sub-state, no manager
## pushing commands into skulls — they just read these values themselves.

@export var skull_scene: PackedScene
@export var max_skulls: int = 20
@export var player: Node3D
@export var spawn_interval: float = 1.0     # one skull every N seconds

# ─── Glide path ───
@export var glide_speed: float = 22.0
@export var glide_turn_speed: float = 0.8
@export var glide_radius_min: float = 20.0
@export var glide_radius_max: float = 35.0
@export var glide_height_min: float = 10.0
@export var glide_height_max: float = 18.0

# ─── Attacks ───
@export var attack_interval_min: float = 6.0
@export var attack_interval_max: float = 10.0
@export var attack_duration: float = 2.5
@export var attack_speed: float = 45.0

enum AttackType { SWEEP, DIVE }

# Shared flock data — Skull.gd reads these every frame.
var swarm_center: Vector3 = Vector3.ZERO
var is_attacking: bool = false
var formation_compression: float = 0.0
var current_attack: AttackType = AttackType.SWEEP

var _swarm_velocity: Vector3 = Vector3.ZERO
var _glide_target: Vector3 = Vector3.ZERO
var _glide_timer: float = 0.0
var _glide_segment: float = 10.0

var _attack_timer: float = 0.0
var _next_attack_time: float = 8.0
var _attack_phase: float = 0.0
var _attack_start: Vector3 = Vector3.ZERO
var _attack_end: Vector3 = Vector3.ZERO

var slot_taken: Array[bool] = []
var _spawn_timer: float = 0.0

func _ready() -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player")

	var anchor: Vector3 = player.global_position if player else global_position
	swarm_center = anchor + Vector3(0, 15, -25)
	_glide_target = swarm_center
	_next_attack_time = randf_range(attack_interval_min, attack_interval_max)

	slot_taken.resize(max_skulls)
	slot_taken.fill(false)

func _physics_process(delta: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return

	if is_attacking:
		_run_attack(delta)
	else:
		_update_glide(delta)
		_attack_timer += delta
		if _attack_timer >= _next_attack_time:
			_start_attack()

	_update_spawning(delta)

# ─── Glide ───

func _update_glide(delta: float) -> void:
	_glide_timer += delta
	if _glide_timer >= _glide_segment or swarm_center.distance_to(_glide_target) < 3.0:
		_pick_glide_target()

	var dir: Vector3 = (_glide_target - swarm_center).normalized()
	_swarm_velocity = _swarm_velocity.lerp(dir * glide_speed, glide_turn_speed * delta)
	swarm_center += _swarm_velocity * delta

	formation_compression = move_toward(formation_compression, 0.0, delta)

func _pick_glide_target() -> void:
	_glide_timer = 0.0
	_glide_segment = randf_range(8.0, 16.0)
	var angle: float = randf_range(0.0, TAU)
	var radius: float = randf_range(glide_radius_min, glide_radius_max)
	var height: float = randf_range(glide_height_min, glide_height_max)
	_glide_target = player.global_position + Vector3(cos(angle) * radius, height, sin(angle) * radius)

# ─── Attack ───

func _start_attack() -> void:
	is_attacking = true
	_attack_phase = 0.0
	current_attack = (randi() % AttackType.size()) as AttackType

	var p: Vector3 = player.global_position
	if current_attack == AttackType.SWEEP:
		var side: float = 1.0 if randf() < 0.5 else -1.0
		_attack_start = p + Vector3(-side * 30.0, 8.0, -8.0)
		_attack_end = p + Vector3(side * 30.0, 8.0, -8.0)
	else:
		_attack_start = p + Vector3(0.0, 22.0, -25.0)
		_attack_end = p + Vector3(0.0, 4.0, 20.0)

	swarm_center = _attack_start

func _run_attack(delta: float) -> void:
	_attack_phase += delta / attack_duration
	var t: float = clamp(_attack_phase, 0.0, 1.0)
	var eased: float = t * t * (3.0 - 2.0 * t)
	swarm_center = _attack_start.lerp(_attack_end, eased)

	formation_compression = 1.0 if t < 0.85 else lerp(1.0, 0.3, (t - 0.85) / 0.15)

	if _attack_phase >= 1.0:
		is_attacking = false
		_attack_timer = 0.0
		_next_attack_time = randf_range(attack_interval_min, attack_interval_max)
		_pick_glide_target()

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
	skull.global_position = global_position   # spawns from wherever you place the Spawner node
	get_tree().current_scene.add_child(skull)

	if skull.has_method("initialize"):
		skull.initialize(self, player, slot, max_skulls)

func notify_skull_died(slot: int) -> void:
	if slot >= 0 and slot < slot_taken.size():
		slot_taken[slot] = false
