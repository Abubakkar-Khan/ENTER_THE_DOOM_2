extends Button


@export var hover_color := Color(0.0, 0.0, 0.0, 0.5)
@export var normal_color := Color(0.75, 0.75, 0.75, 0.0)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_exit)
	
func _on_pressed():
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	


func _on_hover():
	modulate = hover_color

func _on_exit():
	modulate = normal_color
