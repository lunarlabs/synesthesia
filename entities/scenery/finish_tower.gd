extends Node3D

var spin_up_time: float
var _bpm: float
var speed: float

func set_speed(bpm: float = 120):
	spin_up_time = (60.0 / bpm) * 8
	_bpm = bpm

@warning_ignore("unused_parameter")
func _on_song_song_finished(stats: Variant) -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	var tween = create_tween()
	tween.tween_property(self, "speed", 0.375 * _bpm, spin_up_time).set_ease(Tween.EASE_IN)\
	.set_trans(Tween.TRANS_QUAD)

func _process(delta: float) -> void:
	$rotator.rotation_degrees.y += speed * delta
