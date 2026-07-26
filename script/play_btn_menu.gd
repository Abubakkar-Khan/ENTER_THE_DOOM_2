extends Button

# Variables you can change in the Inspector
@export var pulse_speed: float = 10.0      # How fast it flickers
@export var glow_intensity: float = 6.0    # How bright the red gets
@export var base_red: Color = Color(1, 0, 0) # Normal Red (1.0 brightness)
@export_file("*.tscn") var game_scene_path: String # This lets you pick the file in the Inspector

@export var hover_color := Color(0.0, 0.0, 0.0, 0.5)
@export var normal_color := Color(0.75, 0.75, 0.75, 0.0)

@onready var death_fade: ColorRect = $"../../DeathFade"

var is_hovered: bool = false # A "switch" to tell if the mouse is there
var time: float = 0.0        # Keeps track of time for the animation
var _is_fading: bool = false # Prevents double-clicking during the fade transition

func _ready():
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_exit)
	
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	pressed.connect(_on_pressed)
	
	add_theme_color_override("font_color", base_red)
	
	# Ensure the fade starts fully transparent
	if death_fade:
		death_fade.color.a = 0.0
		death_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _on_mouse_entered():
	is_hovered = true

func _on_mouse_exited():
	is_hovered = false
	add_theme_color_override("font_color", base_red)

func _on_pressed():
	if _is_fading:
		return
	_is_fading = true

	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("PRESSED PLAY")
	
	# Use inspector path, or fallback to default if empty
	var target_scene = game_scene_path if game_scene_path != "" else "res://scenes/TerrainController.tscn"
	
	# SAFETY CHECK: Don't fade to black if the scene doesn't exist
	if not ResourceLoader.exists(target_scene):
		print("ERROR: Scene does not exist at '", target_scene, "'. Check your Inspector!")
		_is_fading = false
		return

	# --- SLOW GRADUAL BLACK SCREEN (USING YOUR DEATH_FADE NODE) ---
	
	# Reset alpha to 0 before starting (in case it's leftover from a previous fade)
	if death_fade:
		death_fade.color.a = 0.0

	# Slow motion
	var slow = create_tween()
	slow.set_ignore_time_scale(true)
	slow.tween_property(Engine, "time_scale", 0.15, 0.3)

	# Wait a bit
	await get_tree().create_timer(0.2, true, false, true).timeout

	# Fade to black (using your existing death_fade node)
	var fade = create_tween()
	fade.set_ignore_time_scale(true)
	fade.tween_property(death_fade, "color:a", 1.0, 0.8)

	await fade.finished
	print("Fade complete, changing scene...")

	Engine.time_scale = 1.0
	
	# Change scene
	var err = get_tree().change_scene_to_file(target_scene)
	
	# Fallback: If scene change fails, hide the fade so the player isn't stuck
	if err != OK:
		print("Failed to change scene: ", err)
		death_fade.color.a = 0.0
		_is_fading = false

func _process(delta: float):
	if is_hovered:
		time += delta
		
		var flicker = (sin(time * pulse_speed) + 1.0) / 2.0
		var current_glow = base_red * (1.0 + (flicker * glow_intensity))
		
		add_theme_color_override("font_color", current_glow)

func _on_hover():
	modulate = hover_color

func _on_exit():
	modulate = normal_color
