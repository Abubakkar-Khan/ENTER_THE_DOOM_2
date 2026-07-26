extends CharacterBody3D

# Assign the player in the Inspector
@export var player: Node3D

# Health
@export var health: float = 100.0

# Offset to look at the player's head/chest
@export var look_offset: Vector3 = Vector3(0, 1.5, 0)

@onready var object_4: MeshInstance3D = $"Sketchfab_Scene/Sketchfab_model/44d31179897749b9b13caf2a4d41ec6a_obj_cleaner_gles/Object_2/Object_4"

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

	# --- ADDED: Impact feedback ---
	_flash_eye()
	_flash_screen()

	if health <= 0:
		die()

## Quick white flash on the Eye mesh to sell the hit
func _flash_eye() -> void:
	if object_4 == null:
		return

	if not object_4.has_meta("original_material"):
		object_4.set_meta("original_material", object_4.material_override)

	var flash_material := StandardMaterial3D.new()
	# LOWERED: 1.6x brightness instead of 4x, slight red tint for "wounded" feel
	flash_material.albedo_color = Color(1.6, 1.3, 1.3, 1.0)
	flash_material.emission_enabled = true
	flash_material.emission = Color(1.6, 1.3, 1.3)
	flash_material.emission_energy_multiplier = 1.0  # was 2.0
	
	object_4.material_override = flash_material

	var tween := create_tween()
	# SHORTER: 0.15s instead of 0.25s
	tween.tween_property(flash_material, "albedo_color", Color(1.0, 0.35, 0.35, 1.0), 0.05)
	tween.tween_callback(func():
		object_4.material_override = object_4.get_meta("original_material")
	)
	
## Red screen flash (vignette-style damage feedback)
func _flash_screen() -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("flash_damage"):
		hud.flash_damage()

func die() -> void:
	print("Eye Died!")
	#queue_free()
