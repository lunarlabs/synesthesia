extends PanelContainer


func _on_energy_bar_options_item_selected(index: int) -> void:
	match index:
		0:
			SessionManager.modifiers["energy_modifier"] = SynRoadSongManager.EnergyModifiers.NORMAL
		1:
			SessionManager.modifiers["energy_modifier"] = SynRoadSongManager.EnergyModifiers.DRAIN
		2:
			SessionManager.modifiers["energy_modifier"] = SynRoadSongManager.EnergyModifiers.NO_RECOVER
		3:
			SessionManager.modifiers["energy_modifier"] = SynRoadSongManager.EnergyModifiers.SUDDEN_DEATH
		4:
			SessionManager.modifiers["energy_modifier"] = SynRoadSongManager.EnergyModifiers.NO_FAIL
		_:
			SessionManager.modifiers["energy_modifier"] = SynRoadSongManager.EnergyModifiers.NORMAL


func _on_track_reset_options_item_selected(index: int) -> void:
	match index:
		0:
			SessionManager.modifiers["fast_track_reset"] = 12
		1:
			SessionManager.modifiers["fast_track_reset"] = 10
		2:
			SessionManager.modifiers["fast_track_reset"] = 8
		_:
			SessionManager.modifiers["fast_track_reset"] = 12


func _on_timing_options_item_selected(index: int) -> void:
	match index:
		0:
			SessionManager.modifiers["timing_mode"] = SynRoadSongManager.TimingModifiers.NORMAL
		1:
			SessionManager.modifiers["timing_mode"] = SynRoadSongManager.TimingModifiers.LOOSE
		2:
			SessionManager.modifiers["timing_mode"] = SynRoadSongManager.TimingModifiers.STRICT
		_: # Default
			SessionManager.modifiers["timing_mode"] = SynRoadSongManager.TimingModifiers.NORMAL


func _on_checkpoints_button_toggled(toggled_on: bool) -> void:
	# Barrier modes are not selectable; they can only be applied by the future challenge stage system.
	SessionManager.modifiers["checkpoint_mode"] = \
		SynRoadSongManager.CheckpointModifiers.CHECKPOINT if toggled_on \
		else SynRoadSongManager.CheckpointModifiers.NO_CHECKPOINT_RECOVERY


func _on_highlights_button_toggled(toggled_on: bool) -> void:
	SessionManager.modifiers["streak_hints"] = toggled_on


func _on_speed_option_item_selected(index: int) -> void:
	SessionManager.modifiers["constant_velocity_mode"] = index == 1


func _on_speed_slider_value_changed(value: float) -> void:
	# TODO: update SpeedLabel to show correct value
	SessionManager.modifiers["length_multiplier"] = value


func _on_autoblast_button_toggled(toggled_on: bool) -> void:
	SessionManager.modifiers["autoblast"] = toggled_on


func _on_close_button_pressed() -> void:
	hide()
