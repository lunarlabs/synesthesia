extends Decal

func _ready() -> void:
	rotation.y = randf_range(-PI/4, PI/4)
	await get_tree().create_timer(1.0).timeout
	queue_free()
