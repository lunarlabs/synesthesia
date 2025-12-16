extends MeshInstance3D

@onready var timer = $Timer

func flash():
	set_instance_shader_parameter("hit", true)
	timer.start()

func _on_timer_timeout() -> void:
	set_instance_shader_parameter("hit", false)
