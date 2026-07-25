extends Button


@export var hover_color := Color(0.0, 0.0, 0.0, 0.5)
@export var normal_color := Color(0.75, 0.75, 0.75, 0.0)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	print("Ready")
	print(pressed.is_connected(_on_pressed))
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_exit)

	print("Menu script loaded")

func _on_pressed():
	print("MENU PRESSED")

	var err = get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	#var err = get_tree().change_scene_to_file("res://scenes/pause.tscn")
	print(err)


func _on_hover():
	modulate = hover_color

func _on_exit():
	modulate = normal_color
