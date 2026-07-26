#extends CharacterBody3D
#
#signal zombie_died 
#
#@export var health: float = 3 # Faster for intense action
#
#@export var movement_speed: float = 5.5 # Faster for intense action
#@export var attack_range: float = 2.5   # Tighter range for better combat feel
#
## Matches your model structure from the screenshots
#@onready var anim_player: AnimationPlayer = $Sketchfab_Scene/AnimationPlayer
#@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
#@onready var sketchfab_scene: Node3D = $Sketchfab_Scene
#@onready var death_particles: CPUParticles3D = $death_particles
#@onready var explosion_sound: AudioStreamPlayer2D = $explosion_sound
#
#
#var player = null
#var logic_timer = 0.0
#
#func _ready():
	## Finds the player node in your scene tree
	#player = get_tree().root.find_child("ProtoController", true, false)
	#
	## Performance: Disables expensive avoidance calculations for distant enemies
	#nav_agent.avoidance_enabled = false 
#
	## Setup looping for the walk animation
	#if anim_player and anim_player.has_animation("walk"):
		#anim_player.get_animation("walk").loop_mode = Animation.LOOP_LINEAR
#
	## Staggers the initial update so 80 enemies don't lag the start
	#logic_timer = randf_range(0.0, 0.5) 
#
#func _physics_process(delta):
	## Safety check to prevent errors if nodes are missing
	#if not player or not anim_player: return
#
	#logic_timer += delta
	## Performance: Only calculate a new path every 0.3 seconds
	#if logic_timer > 0.3:
		#nav_agent.target_position = player.global_position
		#logic_timer = 0.0
#
	#nav_agent_logic(delta)
#
#func take_damage(amount: int):
	#health -= amount
	#print("Zombie health: ", health)
	#
	#if health <= 0:
		#sketchfab_scene.visible = false
		#if death_particles and not death_particles.emitting:
			#print("death_particles")
			#death_particles.emitting = true
		#if explosion_sound and not explosion_sound.playing:
			#explosion_sound.play() # PLAY THIS IMMEDIATELY
			#
		#$CollisionShape3D.disabled = true
		#set_physics_process(false)
		#await get_tree().create_timer(2.0).timeout 
		#queue_free()
#
#func nav_agent_logic(delta):
	#var dist = global_position.distance_to(player.global_position)
	#
	#if dist <= attack_range:
		## Stop and attack if close enough
		#velocity = Vector3.ZERO
		#play_anim("attack", 0.2)
	#else:
		## Get path from Navigation Mesh
		#var next_location = nav_agent.get_next_path_position()
		#var dir = (next_location - global_position).normalized()
		#
		## --- ULTIMATE OPTIMIZATION FOR 80+ ENEMIES ---
		## If within 12 meters, use physics to prevent walking through walls/player
		#if dist < 4.0:
			#velocity = dir * movement_speed
			#move_and_slide()
		#else:
			## If far away, bypass physics engine entirely to save CPU
			#global_position += dir * movement_speed * delta
		#
		#play_anim("walk", 0.1) 
#
	#look_at_player()
#
#func play_anim(anim_name, blend):
	#if anim_player == null or anim_player.current_animation == anim_name:
		#return
	#if anim_player.has_animation(anim_name):
		#anim_player.play(anim_name, blend)
#
#func look_at_player():
	#var target_pos = player.global_position
	## Keep the enemy upright by ignoring the Y-axis of the player
	#target_pos.y = global_position.y 
	#if global_position.distance_to(target_pos) > 0.1:
		#look_at(target_pos, Vector3.UP)
		## Corrects model facing
		#rotate_y(deg_to_rad(180))
