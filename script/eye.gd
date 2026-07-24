extends Node3D

# Assign the player in the Inspector
@export var player: Node3D 

# Offset to look at the head/chest instead of the feet
@export var look_offset: Vector3 = Vector3(0, 1.5, 0) 

func _ready() -> void:
	if player == null:
		printerr("EYE ERROR: The Player slot is empty! Assign it in the Inspector.")
	else:
		print("EYE SUCCESS: Player assigned.")

func _process(_delta: float) -> void:
	if player == null:
		return 
		
	# 1. Calculate the exact point in space (Player pos + your offset)
	var target_pos = player.global_position + look_offset
	
	# 2. Get the direction to see if we are looking perfectly straight down
	var dir = global_position.direction_to(target_pos)
	
	# 3. Prevent the engine from breaking if staring straight at the ground
	var up_vec = Vector3.UP
	if abs(dir.y) > 0.99:
		up_vec = Vector3.FORWARD
		
	# 4. Brute-force snap to that exact point
	look_at(target_pos, up_vec)
