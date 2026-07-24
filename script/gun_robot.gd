# Save this as Gun_Robot.gd
extends Node3D

@onready var anim_player: AnimationPlayer = $Sketchfab_Scene/AnimationPlayer
@onready var sfx_gunshot: AudioStreamPlayer3D = $Sketchfab_Scene/AudioStreamPlayer3D

func idle_animation():
	if anim_player.has_animation("Armature|Idle"):
		anim_player.play("Armature|Idle")
	else:
		print("Animations found: ", anim_player.get_animation_list())

func play_shoot():
	if anim_player.has_animation("Armature|Fire"):
		# High speed scale (3.0+) makes the animation "snappy"
		anim_player.speed_scale = 3.5 
		anim_player.play("Armature|Fire", 0.02) # Very small blend for instant response

func play_gun_sound():
	if sfx_gunshot:
		# Randomize pitch slightly so it's not repetitive (CS Student trick!)
		sfx_gunshot.pitch_scale = randf_range(0.9, 1.1)
		sfx_gunshot.play()
		
func handle_movement_animations(is_moving: bool, is_sprinting: bool, is_in_air: bool):
	# 1. THE SHOOTING PROTECTOR
	# If we are currently firing, force speed to normal and STOP this function
	if anim_player.current_animation == "Armature|Fire" and anim_player.is_playing():
		anim_player.speed_scale = 1.0 # Ensure the gun fires at full speed
		return

	# 2. AIR LOGIC
	if is_in_air:
		if anim_player.current_animation != "Armature|Run":
			anim_player.play("Armature|Run", 0.5) 
		anim_player.speed_scale = 0.2 # Only slows down the Run anim
		return

	# 3. GROUND LOGIC
	if not is_moving:
		# Reset speed to normal when landing/stopping
		anim_player.speed_scale = 1.0 
		
		if anim_player.current_animation == "Armature|Run":
			anim_player.play("Armature|AfterRun", 0.1)
			anim_player.queue("Armature|Idle")
		elif anim_player.current_animation != "Armature|AfterRun" and anim_player.current_animation != "Armature|Idle":
			anim_player.play("Armature|Idle", 0.2)
	else:
		if anim_player.current_animation != "Armature|Run":
			anim_player.play("Armature|Run", 0.3)
		
		# Normal ground speeds
		anim_player.speed_scale = 1.5 if is_sprinting else 0.8
