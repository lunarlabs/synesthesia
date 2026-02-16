@tool
extends Resource
class_name SongData
## Represents the data for a song in the game.
##
## This class stores all the metadata and configuration needed to play a song,
## including MIDI file reference, song information, track data, timing settings,
## and audio resources.

const MICROSECONDS_PER_MINUTE = 60_000_000.0
const MIDI_META_TEMPO_EVENT = 0x51

##Path to the MIDI file for this song
@export_file("*.mid") var midi_file

@export_category("Song Info")

##Short title of the song
@export var title: String = "Unknown Track"

## Subtitle of the song
@export var sub_title: String = ""

## Name of the artist or composer
@export var artist: String = "Unknown Artist"

##  Musical genre classification
@export var genre: String = "Unknown Genre"

## The game the song is from
@export var source: String = ""

@export var cover_art: Texture2D

## Description or background information about the song
@export_multiline var description: String

@export_category("Tracks and Audio")

## Array of SongTrackData resources representing each track in the song
@export var tracks: Array[SongTrackData]

## Path to the audio file for the song's main track
@export_file("*.wav","*.mp3","*.ogg") var click_track = ""

@export_file("*.wav","*.mp3","*.ogg") var preview_audio = ""

@export_file("*.wav","*.mp3","*.ogg") var selection_audio = "res://assets/transition.mp3"

@export_category("Gameplay")

@export_range(0.5, 2.0, 0.1) var scale_fudge_factor: float = 1.0

## Number of measures to lead in before gameplay starts
@export_range(0,500,1) var lead_in_measures: int = 4

## Number of playable measures in the song
@export_range(0,500,1) var playable_measures: int = 100

## Array of measure indices where checkpoints occur
@export var checkpoints: Array[int]

## Whether to use a fixed BPM value instead of reading from the MIDI file
@export var bpm_fix: bool = false

## Fixed BPM value to use if bpm_fix is true
@export var fixed_bpm: float = 120.0

var _bpm = NAN
var _err = Error.ERR_INVALID_DATA

var long_title: String:
	get:
		return "%s %s" % [title, sub_title]

var midi_error: Error:
	get:
		if not _midi_data:
			_load_midi_data()
		return _err

var _midi_data: MidiResource
var ticks_per_beat: int:
	get:
		if !_midi_data:
			_load_midi_data()
		return _midi_data.division

var midi_data: MidiResource:
	get:
		if !_midi_data:
			_load_midi_data()
		return _midi_data

## An array containing the names of all tracks in the song.
## Each element represents a unique track identifier or name.
var track_names: Array[String]:
	get:
		if !_midi_data:
			_load_midi_data()
		var names: Array[String] = []
		for i in _midi_data.tracks.size():
			for event in _midi_data.tracks[i].events:
				if event["type"] == "meta" and event["subtype"] == 3:
					names.append(event["data"])
					break
		if names.size() == 0:
			push_warning("No track names found in MIDI data.")
		return names

## A dictionary mapping song track names to their storage locations.
## 
## Keys are track names (String) and values are integer location identifiers.
## Used to store and retrieve the physical or logical location of each track in the song.
var song_track_locations: Dictionary[String, int]:
	get:
		call_deferred("_get_song_track_locations")
		return _get_song_track_locations()

## The beats per minute (BPM) of the song.
## This value determines the tempo/speed of the music.
var bpm: float:
	get:
		if bpm_fix:
			return fixed_bpm
		elif !_midi_data:
			_load_midi_data()
		if is_nan(_bpm):
			for event in _midi_data.tracks[0].events:
				if event["type"] == "meta" and event["subtype"] == MIDI_META_TEMPO_EVENT:
					_bpm = MICROSECONDS_PER_MINUTE / float(event["data"])
			if is_nan(_bpm):
				push_warning("No tempo event found in MIDI data.")
				return 120.0  # Default BPM if not found
		return _bpm

## The duration of one beat in seconds.
## Calculated as 60.0 / BPM (beats per minute).
## Used for timing-related calculations in rhythm-based gameplay.
var seconds_per_beat: float:
	get:
		if bpm_fix:
			return 60.0 / fixed_bpm
		else:
			return 60 / bpm

var total_measures: int:
	get:
		return lead_in_measures + playable_measures

## Returns a dictionary mapping timestamps to note values for a specific track and difficulty.
##
## This function retrieves the note mapping for a given track at a specified difficulty level.
## The difficulty offset adjusts which difficulty tier of notes to retrieve.
##
## @param track: The track index to get notes from
## @param difficulty_offset: The offset value to determine the difficulty level
## @return: A Dictionary where keys are timestamps (float) and values are note identifiers (int)
func get_note_map_from_track(track: int, difficulty_offset: int) -> Dictionary[float, int]:
	var note_map: Dictionary[float, int] = {}
	var valid_note_positions:Array[int] = [difficulty_offset, difficulty_offset + 2, difficulty_offset + 4]
	var tick := 0
	for i in _midi_data.tracks[track].events.size():
		var event = _midi_data.tracks[track].events[i]
		tick += event.delta
		if event.subtype == MIDI_MESSAGE_NOTE_ON and event.data > 0:
			if valid_note_positions.has(event.note):
				var beat_position: float = float(tick) / float(ticks_per_beat)
				note_map[beat_position] = valid_note_positions.find(event.note)
	note_map.sort()
	if note_map.size() == 0:
		push_warning("No valid notes found in track %d with difficulty offset %d." % [track, difficulty_offset])
	return note_map

func _load_midi_data() -> void:
	_midi_data = MidiResource.new()
	_err = _midi_data.load_file(ResourceUID.ensure_path(midi_file))
	assert(_err == OK)
	if _err != OK:
		push_error("Failed to load MIDI data from %s" % midi_file)

func _get_song_track_locations() -> Dictionary[String, int]:
	if !_midi_data:
		_load_midi_data()
	var locations: Dictionary[String, int] = {}
	var cached_names = track_names
	for i in tracks.size():
		var index = cached_names.find(tracks[i].midi_track_name)
		assert(index != -1, "Track name %s not found in MIDI data." % tracks[i].midi_track_name)
		if index != -1:
			locations[tracks[i].midi_track_name] = index
		else:
			push_error("Track name %s not found in MIDI data." % tracks[i].midi_track_name)
	return locations

func get_audio_stream_synchronized() -> AudioStreamSynchronized:
	var result: AudioStreamSynchronized = AudioStreamSynchronized.new()
	result.stream_count = tracks.size() + 1
	result.set_sync_stream(0, load(click_track))
	result.set_sync_stream_volume(0, -10.)
	for i in tracks.size():
		result.set_sync_stream(i + 1, load(tracks[i].audio_file))
	return result
