extends Control

@onready var bg: TextureRect = $"../TextureRect"

@onready var play: Button = $play_btn
@onready var menu: Button = $menu_btn

const DESIGN_SIZE: Vector2 = Vector2(1920.0, 1080.0)

const PLAY_POS: Vector2 = Vector2(955.0, 800.0)
const MENU_POS: Vector2 = Vector2(955.0, 910.0)

const BUTTON_SIZE: Vector2 = Vector2(680.0, 110.0)

func _ready() -> void:
	update_layout()
	get_viewport().size_changed.connect(update_layout)

func update_layout() -> void:
	var ui_scale: float = minf(
		bg.size.x / DESIGN_SIZE.x,
		bg.size.y / DESIGN_SIZE.y
	)

	var image_size: Vector2 = DESIGN_SIZE * ui_scale
	var image_pos: Vector2 = bg.global_position + (bg.size - image_size) * 0.5

	layout_button(menu, MENU_POS, image_pos, ui_scale)
	layout_button(play, PLAY_POS, image_pos, ui_scale)

func layout_button(
	btn: Button,
	design_pos: Vector2,
	image_pos: Vector2,
	ui_scale: float
) -> void:
	btn.size = BUTTON_SIZE * ui_scale
	btn.position = image_pos + design_pos * ui_scale - btn.size * 0.5
