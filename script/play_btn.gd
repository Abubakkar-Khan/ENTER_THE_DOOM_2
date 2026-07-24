extends Button

# Variables you can change in the Inspector
@export var pulse_speed: float = 10.0      # How fast it flickers
@export var glow_intensity: float = 6.0    # How bright the red gets
@export var base_red: Color = Color(1, 0, 0) # Normal Red (1.0 brightness)
@export_file("*.tscn") var game_scene_path: String # This lets you pick the file in the Inspector

var is_hovered: bool = false # A "switch" to tell if the mouse is there
var time: float = 0.0        # Keeps track of time for the animation

func _ready():
	# This connects the button's "ears" to the script
	# mouse_entered: triggers when the cursor touches the button
	# mouse_exited: triggers when the cursor leaves the button
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	# NEW: Connect the 'pressed' signal
	pressed.connect(_on_pressed)
	
	# Start the button as normal red
	add_theme_color_override("font_color", base_red)

func _on_mouse_entered():
	is_hovered = true  # Turn the switch "ON"

func _on_mouse_exited():
	is_hovered = false # Turn the switch "OFF"
	# Reset the color immediately so it doesn't stay bright
	add_theme_color_override("font_color", base_red)

# This function runs when you CLICK the button
func _on_pressed():
	get_tree().change_scene_to_file("res://scenes/TerrainController.tscn")
	
	if game_scene_path == "":
		print("Error: You haven't chosen a scene in the Inspector!")
		return
		
	# This is the command that switches the game to your terrain scene
	
	
func _process(delta: float):
	# This code runs every single frame
	if is_hovered:
		time += delta # Keep track of passing time
		
		# Math: sin() creates a wave that goes up and down
		# We use it like a "dimmer switch" for the light
		var flicker = (sin(time * pulse_speed) + 1.0) / 2.0
		
		# Multiply the red color by the flicker amount + intensity
		# This pushes the color into "Raw/Linear" brightness (> 1.0)
		var current_glow = base_red * (1.0 + (flicker * glow_intensity))
		
		# Apply that glowing color to the text
		add_theme_color_override("font_color", current_glow)
