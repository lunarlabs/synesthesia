extends Node3D

var gate_location: int
var fadeout_time: float = 2.25
var is_barrier: bool = false
@onready var particles = $GPUParticles3D as GPUParticles3D
@onready var finish_plane = $FinishPlane as MeshInstance3D

func _on_song_new_measure(measure):
	if measure == gate_location - 3:
		var _fadeout_tweener = get_tree().create_tween()\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_fadeout_tweener.tween_property(particles, "amount_ratio", 0.0, fadeout_time)
		_fadeout_tweener.tween_callback(_cut_off_particles)

func _cut_off_particles():
	particles.emitting = false

func set_warning_state(value: bool):
	$GPUParticles3D.visible = !value
	$BarrierParticles.emitting = value
	$Gate/LeftGate/GateHalo.set_instance_shader_parameter("warning", value)
	$Gate/RightGate/GateHalo_001.set_instance_shader_parameter("warning", value)
