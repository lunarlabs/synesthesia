class_name SynRoadConductor
extends Node

const RESYNC_INTERVAL_SECONDS := 0.25

@export var bpm: float = 120.0
@export var input_offset_ms: float = 0.0

var time_elapsed: float
var current_beat: float
var beat_int: int
var current_measure: int
var is_playing: bool = false
var vibration: bool = true

var _audio_player: AudioStreamPlayer
var _seconds_per_beat: float = 0.5
var _resync_time: float = 0.0
var _has_synced_startup: bool = false

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
		
	var audio_time = get_audio_time()
	
	# Wait until the audio thread actually starts pumping data to the speakers
	if not _has_synced_startup:
		if audio_time > 0.0:
			time_elapsed = audio_time # Snap perfectly once
			_has_synced_startup = true
		else:
			return # Do nothing until the audio catches up
	
	time_elapsed += delta * _audio_player.pitch_scale
	_resync_time += delta
	
	if _resync_time >= RESYNC_INTERVAL_SECONDS:
		_resync_time = 0.0
		var drift = time_elapsed - audio_time
		
		if abs(drift) > 0.1:
			# Catastrophic drift (>100ms) — snap immediately
			time_elapsed = audio_time
		elif abs(drift) > 0.03:
			# Large drift (30-100ms) — aggressive correction
			time_elapsed = lerp(time_elapsed, audio_time, 0.5)
		else:
			# Normal drift (<30ms) — gentle correction
			time_elapsed = lerp(time_elapsed, audio_time, 0.3)

	current_beat = time_elapsed / _seconds_per_beat
	if floori(current_beat) > beat_int:
		if vibration:
			Input.start_joy_vibration(0, 1.0, 0.0, 0.1)
		beat_int = floori(current_beat)

	var this_measure = floori(current_beat / 4.0)
	if this_measure > current_measure:
		current_measure = this_measure
		new_measure.emit(current_measure)

func get_audio_time() -> float:
	return _audio_player.get_playback_position() + AudioServer.get_time_since_last_mix() \
	- AudioServer.get_output_latency()
