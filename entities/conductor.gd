class_name SynRoadConductor
extends Node

@export var bpm: float = 120.0
@export var input_offset_ms: float = 0.0

var time_elapsed: float
var current_beat: float
var current_measure: int
var is_playing: bool = false

var _audio_player: AudioStreamPlayer
var _seconds_per_beat: float = 0.5

signal new_measure(measure: int)
signal frame_drop()

func _init() -> void:
	process_priority = -10

func setup(audio_player: AudioStreamPlayer, song_bpm: float):
	_audio_player = audio_player
	bpm = song_bpm
	_seconds_per_beat = 60.0 / song_bpm
	set_process(true)

func _process(delta: float):
	if not is_playing or not _audio_player:
		return
	
	var audio_time = get_audio_time()
	audio_time += (input_offset_ms / 1000.0)

	if time_elapsed > 0:
		var expected_time = time_elapsed + delta
		var drift = audio_time - expected_time

		if abs(drift) > 0.050:  # >50ms drift
			print("FRAME DROP: %.1fms (actual: %.3f, expected: %.3f)" % [drift * 1000, audio_time, expected_time])
			frame_drop.emit()

	time_elapsed = audio_time

	current_beat = time_elapsed / _seconds_per_beat

	var this_measure = floori(current_beat / 4.0)
	if this_measure > current_measure:
		current_measure = this_measure
		new_measure.emit(current_measure)

func get_audio_time() -> float:
	return _audio_player.get_playback_position() + AudioServer.get_time_since_last_mix()
