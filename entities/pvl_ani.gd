extends Label

func _ready():
	hide()
	_reset()
	
func _reset():
	modulate = Color.WHITE
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE

func phrase_passed(value):
	_reset()
	scale = Vector2(1.75, 1.75)
	var tween = create_tween()
	text = str(value)
	show()
	tween.tween_property(self , "scale", Vector2.ONE, 0.2)
	tween.parallel().tween_property(self , "position:y", -200, 1.0)
	tween.parallel().tween_property(self , "modulate:a", 0.0, 1.0)
	tween.tween_callback(hide)

func phrase_failed(value):
	_reset()
	modulate = Color(1, 0.55, 0, 0.75)
	var rotate_val = randf_range(-90, 90)
	var tween = create_tween()
	text = str(value)
	show()
	tween.tween_property(self , "rotation_degrees", rotate_val, 0.75) \
	.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(self , "position:y", 400, 0.75) \
	.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(self , "modulate:a", 0.0, 0.75)
	tween.tween_callback(hide)
