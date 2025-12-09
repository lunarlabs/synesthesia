extends Node3D

var gate_location: int
var _fadeout_started: bool = false
@onready var particles = $GPUParticles3D as GPUParticles3D

func _on_song_new_measure(measure: int):
	if measure == gate_location - 2 and not _fadeout_started:
		_fadeout_started = true
		var tween = get_tree().create_tween()
		tween.tween_property(particles, "amount_ratio", 0, get_parent().seconds_per_beat * 8)
	elif measure == gate_location + 1:
		print("Checkpoint passed at measure %d" % (gate_location + 1))
	elif measure == gate_location + 2:
		queue_free()
	
