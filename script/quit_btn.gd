extends Button

@export var hover_color := Color(0.0, 0.0, 0.0, 0.5)
@export var normal_color := Color(0.75, 0.75, 0.75, 0.0)

func _ready():
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_exit)
	pressed.connect(_on_pressed)

func _on_pressed():
	get_tree().quit()

func _on_hover():
	modulate = hover_color

func _on_exit():
	modulate = normal_color
