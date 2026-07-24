extends Node3D

@export var enemy_template: PackedScene
@export var spawn_radius: float = 25.0
@export var inner_safe_radius: float = 10.0
@export var spawn_delay_min: float = 2.0
@export var spawn_delay_max: float = 4.0
@export var enemies_per_wave_min: int = 2
@export var enemies_per_wave_max: int = 5
@export var player_avoid_distance: float = 15.0

# GLOBAL LIMIT
static var global_max_limit: int = 0

@onready var container = get_tree().root.find_child("EnemyContainer", true, false)
@onready var player = get_tree().root.find_child("ProtoController", true, false)

# ------------------------------

func _enter_tree():
	randomize()
	global_max_limit += 20   # more enemies overall now
	print("Spawner added. Global limit:", global_max_limit)

# ------------------------------

func _ready():
	await get_tree().create_timer(1.0).timeout
	spawn_loop()

# ------------------------------

func spawn_loop():
	while true:
		await get_tree().create_timer(randf_range(spawn_delay_min, spawn_delay_max)).timeout
		
		spawn_wave()

# ------------------------------

func spawn_wave():
	if not player:
		return

	var total_enemies = get_tree().get_nodes_in_group("enemies").size()
	if total_enemies >= global_max_limit:
		return

	var wave_size = randi_range(enemies_per_wave_min, enemies_per_wave_max)

	for i in range(wave_size):
		var spawn_pos = get_random_spawn_around_player()
		if spawn_pos != null:
			spawn_enemy(spawn_pos)

# ------------------------------

func get_random_spawn_around_player():
	for i in range(10):
		var angle = randf() * PI * 2
		
		# Spawn in a ring (NOT too close, NOT too far)
		var distance = randf_range(inner_safe_radius, spawn_radius)
		
		var offset = Vector3(cos(angle) * distance, 0, sin(angle) * distance)
		var pos = player.global_position + offset

		# Avoid spawning too close
		if pos.distance_to(player.global_position) < player_avoid_distance:
			continue

		# Navmesh safe
		var map = get_world_3d().get_navigation_map()
		var safe_pos = NavigationServer3D.map_get_closest_point(map, pos)

		if safe_pos != Vector3.ZERO:
			return safe_pos

	return null

# ------------------------------

func spawn_enemy(pos: Vector3):
	if not enemy_template:
		return

	var new_zombie = enemy_template.instantiate()
	new_zombie.global_position = pos
	new_zombie.add_to_group("enemies")

	if container:
		container.add_child(new_zombie)
	else:
		get_tree().root.add_child(new_zombie)

# ------------------------------

func _exit_tree():
	global_max_limit -= 20
	print("Spawner removed. Global limit:", global_max_limit)
