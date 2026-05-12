extends PanelContainer

signal closed

@onready var energy_bar_options = $GridContainer/EnergyBarOptions
@onready var track_reset_options = $GridContainer/TrackResetOptions
@onready var timing_options = $GridContainer/TimingOptions
@onready var checkpoints_button = $GridContainer/CheckpointsButton
@onready var highlights_button = $GridContainer/HighlightsButton
@onready var speed_options = $GridContainer/SpeedOption
@onready var speed_slider = $GridContainer/SpeedSlider
@onready var speed_label = $GridContainer/SpeedLabel
@onready var autoblast_button = $GridContainer/AutoblastButton

var previous_checkpoint_choice: bool
var dont_set_multiplier_value: bool = false

func _ready() -> void:
	# set modifier options based on what's saved in SessionManager
	var energy_modifier = SessionManager.modifiers.get("energy_modifier", SynRoadSongManager.EnergyModifiers.NORMAL)
	var fast_track_reset = SessionManager.modifiers.get("fast_track_reset", SynRoadSongManager.TrackReset.NORMAL)
	var timing_mode = SessionManager.modifiers.get("timing_mode", SynRoadSongManager.TimingModifiers.NORMAL)
	var checkpoint_mode = SessionManager.modifiers.get("checkpoint_mode", SynRoadSongManager.CheckpointModifiers.CHECKPOINT)
	previous_checkpoint_choice = (checkpoint_mode != SynRoadSongManager.CheckpointModifiers.NO_CHECKPOINT_RECOVERY)
	var streak_hints = SessionManager.modifiers.get("streak_hints", true)
	var constant_velocity_mode = SessionManager.modifiers.get("constant_velocity_mode", false)
	var length_multiplier = SessionManager.modifiers.get("length_multiplier", 1.0)
	var autoblast = SessionManager.modifiers.get("autoblast", false)

	# Now, we essentially do the reverse of the modifier setting in the event functions
	match energy_modifier:
		SynRoadSongManager.EnergyModifiers.NORMAL:
			energy_bar_options.select(0)
		SynRoadSongManager.EnergyModifiers.DRAIN:
			energy_bar_options.select(1)
		SynRoadSongManager.EnergyModifiers.NO_RECOVER:
			energy_bar_options.select(2)
		SynRoadSongManager.EnergyModifiers.SUDDEN_DEATH:
			energy_bar_options.select(3)
		SynRoadSongManager.EnergyModifiers.NO_FAIL:
			energy_bar_options.select(4)
		_:
			energy_bar_options.select(0)
	
	var hardcore = energy_modifier in [
		SynRoadSongManager.EnergyModifiers.NO_RECOVER,
		SynRoadSongManager.EnergyModifiers.SUDDEN_DEATH
	]
	
	match fast_track_reset:
		SynRoadSongManager.TrackReset.NORMAL:
			track_reset_options.select(0)
		SynRoadSongManager.TrackReset.FAST_ONE:
			track_reset_options.select(1)
		SynRoadSongManager.TrackReset.FAST_TWO:
			track_reset_options.select(2)
		_:
			track_reset_options.select(0)
			
	match timing_mode:
		SynRoadSongManager.TimingModifiers.NORMAL:
			timing_options.select(1)
		SynRoadSongManager.TimingModifiers.LOOSE:
			timing_options.select(0)
		SynRoadSongManager.TimingModifiers.STRICT:
			timing_options.select(2)
		_:
			timing_options.select(1)
	
	if hardcore:
		checkpoints_button.button_pressed = false
		checkpoints_button.disabled = true
	else:
		checkpoints_button.button_pressed = (checkpoint_mode != SynRoadSongManager.CheckpointModifiers.NO_CHECKPOINT_RECOVERY)
	
	highlights_button.button_pressed = streak_hints
	
	_change_velocity_mode(constant_velocity_mode)
	if constant_velocity_mode:
		speed_options.select(1)
		speed_slider.value = 120 * length_multiplier
	else:
		speed_options.select(0)
		speed_slider.value = length_multiplier
	_update_velocity_label()
	
	autoblast_button.button_pressed = autoblast

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
	var hardcore = (index in [2, 3])
	if hardcore:
		checkpoints_button.button_pressed = false
		checkpoints_button.disabled = true
	elif checkpoints_button.disabled:
		checkpoints_button.disabled = false
		checkpoints_button.button_pressed = previous_checkpoint_choice


func _on_track_reset_options_item_selected(index: int) -> void:
	match index:
		0:
			SessionManager.modifiers["fast_track_reset"] = SynRoadSongManager.TrackReset.NORMAL
		1:
			SessionManager.modifiers["fast_track_reset"] = SynRoadSongManager.TrackReset.FAST_ONE
		2:
			SessionManager.modifiers["fast_track_reset"] = SynRoadSongManager.TrackReset.FAST_TWO
		_:
			SessionManager.modifiers["fast_track_reset"] = 12


func _on_timing_options_item_selected(index: int) -> void:
	match index:
		0:
			SessionManager.modifiers["timing_mode"] = SynRoadSongManager.TimingModifiers.LOOSE
		1:
			SessionManager.modifiers["timing_mode"] = SynRoadSongManager.TimingModifiers.NORMAL
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
	var mode = (index == 1)
	SessionManager.modifiers["constant_velocity_mode"] = mode
	_change_velocity_mode(mode)
	_update_velocity_label()
	SessionManager.modifiers["length_multiplier"] = 1.0


func _on_speed_slider_value_changed(value: float) -> void:
	_update_velocity_label()


func _on_autoblast_button_toggled(toggled_on: bool) -> void:
	SessionManager.modifiers["autoblast"] = toggled_on


func _on_close_button_pressed() -> void:
	hide()
	closed.emit()
	
func _change_velocity_mode(constant_velocity: bool):
	if constant_velocity:
		speed_slider.min_value = 90.0
		speed_slider.max_value = 240.0
		speed_slider.step = 15.0
		speed_slider.value = 120.0
	else:
		speed_slider.min_value = 0.5
		speed_slider.max_value = 2.0
		speed_slider.step = 0.25
		speed_slider.value = 1.0
	
func _update_velocity_label():
	var mode = SessionManager.modifiers.get("constant_velocity_mode", false)
	if mode:
		speed_label.text = "%d BPM" % speed_slider.value
	else:
		speed_label.text = "%sx" % speed_slider.value


func _on_speed_slider_drag_ended(value_changed: bool) -> void:
	if value_changed:
		if speed_options.selected == 1:
			SessionManager.modifiers["length_multiplier"] = speed_slider.value / 120.0
		else:
			SessionManager.modifiers["length_multiplier"] = speed_slider.value
