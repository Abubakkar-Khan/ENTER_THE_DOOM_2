extends CanvasLayer

@onready var timer_label: Label = $Timer_Label
@onready var score_label: Label = $Score_Label
@onready var health_bar: ProgressBar = $"../HealthBar"
@onready var eye_health_bar: ProgressBar = $"../eye_HealthBar"

const DESIGN_SIZE := Vector2(1920, 1080)

# Margins (change these)
const TOP_MARGIN := 65.0
const SIDE_MARGIN := 80.0
const BOTTOM_MARGIN := 50.0
const HEALTH_WIDTH := 288.0
const HEALTH_HEIGHT := 11.0

const EYE_TOP_MARGIN := 130.0
const EYE_WIDTH := 570.0
const EYE_HEIGHT := 15.0


func _ready():
	update_layout()
	get_viewport().size_changed.connect(update_layout)

func _process(_delta):
	eye_health_bar.health = GameData.eye_health

func update_layout():
	var viewport_size = get_viewport().get_visible_rect().size
	var ui_scale = min(
		viewport_size.x / DESIGN_SIZE.x,
		viewport_size.y / DESIGN_SIZE.y
	)

	# Score (top-left)
	score_label.position = Vector2(
		SIDE_MARGIN * ui_scale,
		TOP_MARGIN * ui_scale
	)

	# Timer (top-right)
	timer_label.position = Vector2(
		viewport_size.x - timer_label.size.x - SIDE_MARGIN * ui_scale,
		TOP_MARGIN * ui_scale
	)

	# Health Bar (bottom-left)
	health_bar.position = Vector2(
		(SIDE_MARGIN + 69) * ui_scale,
		viewport_size.y - health_bar.size.y - (BOTTOM_MARGIN + 13) * ui_scale
	)
	health_bar.size = Vector2(
		HEALTH_WIDTH * ui_scale,
		HEALTH_HEIGHT * ui_scale
	)
		# Scale text
	score_label.add_theme_font_size_override("font_size", int(48 * ui_scale))
	timer_label.add_theme_font_size_override("font_size", int(48 * ui_scale))
	
	eye_health_bar.size = Vector2(
		EYE_WIDTH * ui_scale,
		EYE_HEIGHT * ui_scale
	)

	eye_health_bar.position = Vector2(
		(viewport_size.x - 10 - eye_health_bar.size.x) * 0.5,
		EYE_TOP_MARGIN * ui_scale
	)
