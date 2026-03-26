extends CanvasLayer

signal animation_completed

func start_transition_in():
	if !visible:
		show()
	$AnimationPlayer.play("build_in")

func start_transition_out():
	if visible:
		$AnimationPlayer.play("build_out")

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	animation_completed.emit()
	if anim_name == "build_out":
		hide()
