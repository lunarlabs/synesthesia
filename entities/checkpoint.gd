extends Node3D

var gate_location: int
var fadeout_time: float = 1.0
@onready var particles = $GPUParticles3D as GPUParticles3D

func _on_song_new_measure(measure):
	if measure == gate_location - 2:
		var _fadeout_tweener = get_tree().create_tween()\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_fadeout_tweener.tween_property(particles, "amount_ratio", 0.0, fadeout_time)
		_fadeout_tweener.tween_callback(_cut_off_particles)

func _cut_off_particles():
	particles.emitting = false
