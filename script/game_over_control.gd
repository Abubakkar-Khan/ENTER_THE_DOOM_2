extends Control

@onready var bg: TextureRect = $"../TextureRect"

@onready var play: Button = $play_btn
@onready var menu: Button = $menu_btn
@onready var score_label: Label = $ScoreLabel
@onready var time_label: Label = $TimeLabel

const DESIGN_SIZE: Vector2 = Vector2(1920.0, 1080.0)

const PLAY_POS: Vector2 = Vector2(955.0, 800.0)
const MENU_POS: Vector2 = Vector2(955.0, 910.0)

const BUTTON_SIZE: Vector2 = Vector2(680.0, 110.0)
const LABEL_SIZE: Vector2 = Vector2(300.0, 100.0)

func _ready() -> void:
	update_layout()
	get_viewport().size_changed.connect(update_layout)

	score_label.text = str(GameData.score)
	time_label.text = str(int(GameData.survival_time)) + " s"

func update_layout() -> void:
	var ui_scale: float = minf(
		bg.size.x / DESIGN_SIZE.x,
		bg.size.y / DESIGN_SIZE.y
	)

	var image_size: Vector2 = DESIGN_SIZE * ui_scale
	var image_pos: Vector2 = bg.global_position + (bg.size - image_size) * 0.5

	# Buttons
	layout_button(play, PLAY_POS, image_pos, ui_scale)
	layout_button(menu, MENU_POS, image_pos, ui_scale)

	# Labels (relative to center of the background)
	var center := image_pos + image_size * 0.5

	layout_label(score_label, center + Vector2(-300 * ui_scale, 120 * ui_scale), ui_scale)
	layout_label(time_label, center + Vector2(310 * ui_scale, 120 * ui_scale), ui_scale)

func layout_button(
	btn: Button,
	design_pos: Vector2,
	image_pos: Vector2,
	ui_scale: float
) -> void:
	btn.size = BUTTON_SIZE * ui_scale
	btn.position = image_pos + design_pos * ui_scale - btn.size * 0.5

func layout_label(lbl: Label, pos: Vector2, ui_scale: float) -> void:
	lbl.size = LABEL_SIZE * ui_scale
	lbl.position = pos - lbl.size * 0.5

	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	lbl.add_theme_font_size_override("font_size", int(48 * ui_scale))
