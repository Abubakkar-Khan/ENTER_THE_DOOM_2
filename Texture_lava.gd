@tool

extends Control

@export var speed := Vector2(0.2, 0.0)
var offset := Vector2.ZERO

func _process(delta):
	offset += speed * delta

	var tex: Texture2D = $TextureRect.texture

	if tex is NoiseTexture2D:
		tex.noise.offset = offset
		tex.changed.emit()
