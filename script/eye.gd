extends CharacterBody3D

# Assign the player in the Inspector
@export var player: Node3D

# Health
@export var health: float = 100.0

# Offset to look at the player's head/chest
@export var look_offset: Vector3 = Vector3(0, 1.5, 0)

func _ready() -> void:
	GameData.eye_health = health
	if player == null:
		printerr("EYE ERROR: The Player slot is empty! Assign it in the Inspector.")
	else:
		print("EYE SUCCESS: Player assigned.")

func _process(_delta: float) -> void:
	if player == null:
		return

	var target_pos = player.global_position + look_offset
	var dir = global_position.direction_to(target_pos)

	var up_vec = Vector3.UP
	if abs(dir.y) > 0.99:
		up_vec = Vector3.FORWARD

	look_at(target_pos, up_vec)

func take_damage(amount: float) -> void:
	health -= (amount * 0.5)
	GameData.eye_health = health
	print("Eye Health:", int(health))

	if health <= 0:
		die()

func die() -> void:
	print("Eye Died!")
	
	#queue_free()
