extends ProgressBar

@onready var damage: ProgressBar = $damage
@onready var timer: Timer = $Timer

var health = 0 : set = _set_health

func _set_health(new_health):
	var prev_health = health
	health = min(max_value, new_health)
	value = health
	
	if  health <= 0:
		queue_free()
		
	if health < prev_health:
		timer.start()
	else:
		damage.value = health
		

func init_health(_health):
	health = _health
	max_value = health
	value = health
	damage.max_value = health 
	damage.value = health


func _on_timer_timeout() -> void:
	damage.value = health 
