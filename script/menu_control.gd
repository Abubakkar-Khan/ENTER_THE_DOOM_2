extends Control

@onready var bg: TextureRect = $"../TextureRect"

# Your existing 2D audio player (used for both hover and click now)
@onready var hover_sfx: AudioStreamPlayer2D = $"../AudioStreamPlayer2D"

@onready var play: Button = $play_btn
@onready var quit: Button = $Quit_btn

const DESIGN_SIZE: Vector2 = Vector2(1920.0, 1080.0)
const PLAY_POS: Vector2 = Vector2(955.0, 725.0)
const QUIT_POS: Vector2 = Vector2(955.0, 875.0)
const BUTTON_SIZE: Vector2 = Vector2(680.0, 140.0)

func _ready() -> void:
	update_layout()
	get_viewport().size_changed.connect(update_layout)

	# 1. Connect HOVER signals (mouse enters the button)
	play.mouse_entered.connect(_play_hover_sound)
	quit.mouse_entered.connect(_play_hover_sound)

	# 2. Connect CLICK signals (button is pressed)
	play.pressed.connect(_play_click_sound)
	quit.pressed.connect(_play_click_sound)

func _play_hover_sound() -> void:
	hover_sfx.play()

func _play_click_sound() -> void:
	# This will play the click sound when the button is pressed
	hover_sfx.play()

func update_layout() -> void:
	var ui_scale: float = minf(
		bg.size.x / DESIGN_SIZE.x,
		bg.size.y / DESIGN_SIZE.y
	)

	var image_size: Vector2 = DESIGN_SIZE * ui_scale
	var image_pos: Vector2 = bg.global_position + (bg.size - image_size) * 0.5

	layout_button(quit, QUIT_POS, image_pos, ui_scale)
	layout_button(play, PLAY_POS, image_pos, ui_scale)

func layout_button(
	btn: Button,
	design_pos: Vector2,
	image_pos: Vector2,
	ui_scale: float
) -> void:
	btn.size = BUTTON_SIZE * ui_scale
	btn.position = image_pos + design_pos * ui_scale - btn.size * 0.5
