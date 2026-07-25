# ProtoController v1.0 with Health & Damage System
extends CharacterBody3D

## --- HEALTH SYSTEM ---
@export_group("Health Settings")
@export var max_health: float = 100.0
var current_health: float = 100.0
var is_dead: bool = false
@export var lava_damage_rate: float = 15.0 # Health lost per second in lava

## --- MOVEMENT SETTINGS ---
@export var can_move : bool = true
@export var has_gravity : bool = true
@export var can_jump : bool = true
@export var can_sprint : bool = false
@export var can_freefly : bool = false

var can_shoot: bool = true
@export var shoot_cooldown: float = 0.4 

@export_group("Speeds")
@export var look_speed : float = 0.002
@export var base_speed : float = 7.0
@export var jump_velocity : float = 7
@export var sprint_speed : float = 10.0
@export var freefly_speed : float = 25.0

@export_group("Input Actions")
@export var input_left : String = "ui_left"
@export var input_right : String = "ui_right"
@export var input_forward : String = "ui_up"
@export var input_back : String = "ui_down"
@export var input_jump : String = "ui_accept"
@export var input_sprint : String = "sprint"
@export var input_freefly : String = "freefly"
@export var shoot : String = "shoot"

var mouse_captured : bool = false
var look_rotation : Vector2
var move_speed : float = 0.0
var freeflying : bool = false
var is_in_lava: bool = false

var bullet = load("res://scenes/bullet.tscn")


## Score
var score := 0
@onready var score_label: Label = $CanvasLayer/Score_Label

## IMPORTANT REFERENCES
@onready var head: Node3D = $Head
@onready var collider: CollisionShape3D = $Collider
@onready var gun_robot: Node3D = $Head/Camera3D/Gun_Robot2
@onready var run_sound: AudioStreamPlayer3D = $run_sound
@onready var scream_sound: AudioStreamPlayer3D = $scream_sound
@onready var burning_sound: AudioStreamPlayer3D = $burning_sound

@onready var health_bar: ProgressBar = $HealthBar
@onready var death_fade: ColorRect = $CanvasLayer/DeathFade

@onready var game_timer: Timer = $Timer
@onready var timer_label: Label = $CanvasLayer/Timer_Label

func _ready() -> void:
	current_health = max_health
	check_input_mappings()
	capture_mouse() # Start with mouse captured so we can move immediately
	health_bar.init_health(current_health)
	
	look_rotation.y = rotation.y
	look_rotation.x = head.rotation.x
	
	game_timer.timeout.connect(_on_timer_timeout)
	# Attempt to link Lava trigger
	var lava_trigger = get_parent().get_node_or_null("Lava2/Area3D")
	if lava_trigger:
		lava_trigger.body_entered.connect(_on_lava_2_body_entered)
		lava_trigger.body_exited.connect(_on_lava_2_body_exited)
		print("Lava successfully linked!")

func _physics_process(delta: float) -> void:
	if is_dead: return # Stop processing if dead

	# Handle Lava Damage Over Time
	if is_in_lava:
		take_damage(lava_damage_rate * delta)

	# Shooting logic
	if Input.is_action_just_pressed(shoot) and mouse_captured:
		fire_gun()

	if can_freefly and freeflying:
		handle_freefly(delta)
		return
	
	apply_gravity(delta)
	handle_jump()
	handle_movement(delta)
	handle_footsteps()
	
	var time_left := int(game_timer.time_left)
	var minutes := time_left / 60
	var seconds := time_left % 60
	timer_label.text = "%02d:%02d" % [minutes, seconds]

func take_damage(amount: float):
	if is_dead: return
	
	current_health -= amount
	print("Health: ", int(current_health))
	health_bar.health = current_health
	
	if current_health <= 0:
		die()

func die():
	if is_dead:
		return

	is_dead = true
	can_move = false
	can_shoot = false

	if scream_sound:
		scream_sound.play()

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Slow motion
	var slow = create_tween()
	slow.set_ignore_time_scale(true)
	slow.tween_property(Engine, "time_scale", 0.15, 0.5)

	# Wait a bit so the player sees the death
	await get_tree().create_timer(0.4, true, false, true).timeout

	# Fade to black
	var fade = create_tween()
	fade.set_ignore_time_scale(true)
	fade.tween_property(death_fade, "color:a", 1.0, 1.6)

	await fade.finished
	Engine.time_scale = 1.0

	get_tree().change_scene_to_file("res://scenes/game_over.tscn")

# --- MOVEMENT HELPER FUNCTIONS ---

func apply_gravity(delta):
	if has_gravity and not is_on_floor():
		velocity += 1.5 * (get_gravity() * delta)

func handle_jump():
	if can_jump and Input.is_action_just_pressed(input_jump) and is_on_floor():
		velocity.y = jump_velocity

func handle_movement(delta):
	if can_sprint and Input.is_action_pressed(input_sprint):
		move_speed = sprint_speed
	else:
		move_speed = base_speed

	if can_move:
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		var move_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		if move_dir:
			velocity.x = move_dir.x * move_speed
			velocity.z = move_dir.z * move_speed
		else:
			velocity.x = move_toward(velocity.x, 0, move_speed)
			velocity.z = move_toward(velocity.z, 0, move_speed)
	
	move_and_slide()

func handle_freefly(delta):
	var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
	var motion := (head.global_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	motion *= freefly_speed * delta
	move_and_collide(motion)

# --- COMBAT & INPUT ---

func fire_gun():
	if not can_shoot: return
	if gun_robot and gun_robot.has_method("play_shoot"):
		can_shoot = false 
		gun_robot.play_shoot()
		
		var muzzle_ray = gun_robot.get_node_or_null("Sketchfab_Scene/RayCast3D")
		if muzzle_ray:
			if gun_robot.has_method("play_gun_sound"):
				gun_robot.play_gun_sound()
			var bullet_instance = bullet.instantiate()
			bullet_instance.global_transform = muzzle_ray.global_transform
			get_parent().add_child(bullet_instance)
			
		await gun_robot.anim_player.animation_finished
		can_shoot = true

func _unhandled_input(event: InputEvent) -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		capture_mouse()
	if Input.is_key_pressed(KEY_ESCAPE):
		release_mouse()
	
	if mouse_captured and event is InputEventMouseMotion:
		rotate_look(event.relative)

func rotate_look(rot_input : Vector2):
	look_rotation.x -= rot_input.y * look_speed
	look_rotation.x = clamp(look_rotation.x, deg_to_rad(-85), deg_to_rad(85))
	look_rotation.y -= rot_input.x * look_speed
	transform.basis = Basis()
	rotate_y(look_rotation.y)
	head.transform.basis = Basis()
	head.rotate_x(look_rotation.x)

func capture_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true

func release_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	mouse_captured = false

# --- LAVA & TRIGGERS ---

func _on_lava_2_body_entered(body: Node3D) -> void:
	if body == self:
		is_in_lava = true
		base_speed = 2.0
		if not burning_sound.playing:
			burning_sound.play()

func _on_lava_2_body_exited(body: Node3D) -> void:
	if body == self:
		is_in_lava = false
		base_speed = 7.0
		burning_sound.stop()

func handle_footsteps():
	if is_on_floor() and velocity.length() > 0.1:
		if not run_sound.playing:
			run_sound.play()
		run_sound.pitch_scale = 1.0 if velocity.length() > 11.0 else 0.6
	else:
		if run_sound.playing:
			run_sound.stop()

func check_input_mappings():
	var actions = [input_left, input_right, input_forward, input_back]
	for action in actions:
		if not InputMap.has_action(action):
			push_error("Missing Input Action: " + action)


func _on_timer_timeout():
	die()
	
func add_score(points):
	score += points
	score_label.text = str(score)
