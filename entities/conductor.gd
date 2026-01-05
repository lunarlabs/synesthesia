class_name SynRoadConductor
extends Node

@export var bpm: float = 120.0
@export var input_offset_ms: float = 0.0

var time_elapsed: float
var current_beat: float
var current_measure: int
var is_playing: bool = false

var _audio_player: AudioStreamPlayer
var _previous_time: float
var _seconds_per_beat: float = 0.5

signal new_measure(measure)

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

