class_name SynRoadConductor
extends Node

const RESYNC_INTERVAL_SECONDS := 0.25

@export var bpm: float = 120.0
@export var input_offset_ms: float = 0.0

var time_elapsed: float
var current_beat: float
var current_measure: int
var is_playing: bool = false

var _audio_player: AudioStreamPlayer
var _seconds_per_beat: float = 0.5
var _resync_time: float = 0.0

signal new_measure(measure: int)

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
	
	time_elapsed += delta
	_resync_time += delta
	
	if _resync_time >= RESYNC_INTERVAL_SECONDS:
		_resync_time = 0.0
		time_elapsed = lerp(time_elapsed, get_audio_time(), 0.1)

	current_beat = time_elapsed / _seconds_per_beat

	var this_measure = floori(current_beat / 4.0)
	if this_measure > current_measure:
		current_measure = this_measure
		new_measure.emit(current_measure)

func get_audio_time() -> float:
	return _audio_player.get_playback_position() + AudioServer.get_time_since_last_mix()\
	- AudioServer.get_output_latency()
