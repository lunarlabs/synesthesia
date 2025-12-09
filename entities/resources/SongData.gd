@tool
extends Resource
class_name SongData
## Represents the data for a song in the game.
##
## This class stores all the metadata and configuration needed to play a song,
## including MIDI file reference, song information, track data, timing settings,
## and audio resources.

##Path to the MIDI file for this song
@export_file("*.mid") var midi_file

##Short title of the song
@export var title: String

## Full/extended title of the song
@export var long_title: String

## Name of the artist or composer
@export var artist: String

##  Musical genre classification
@export var genre: String

## Description or background information about the song
@export_multiline var description: String

## Array of SongTrackData resources representing each track in the song
@export var tracks: Array[SongTrackData]

@export_range(0.5, 2.0, 0.1) var scale_fudge_factor: float = 1.0

## Number of measures to lead in before gameplay starts
@export_range(0,500,1) var lead_in_measures: int = 4

## Number of playable measures in the song
@export_range(0,500,1) var playable_measures: int = 100

## Array of measure indices where checkpoints occur
@export var checkpoints: Array[int]

## Path to the audio file for the song's main track
@export_file("*.wav") var click_track

## Array of audio file paths for introductory segments before the main track
@export var intro_audio: Array[String]

## Whether to use a fixed BPM value instead of reading from the MIDI file
@export var bpm_fix: bool = false

## Fixed BPM value to use if bpm_fix is true
@export var fixed_bpm: float = 120.0

var _midi_data: MidiData
var ticks_per_beat: int:
	get:
		if !_midi_data:
			_load_midi_data()
		return _midi_data.header.ticks_per_beat

var midi_data: MidiData:
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
			var track_data = _midi_data.tracks[i] as MidiData.Track
			if track_data:
				for event in track_data.events:
					if event is MidiData.TrackName:
						names.append(event.text)
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
		for event in _midi_data.tracks[0].events:
			if event is MidiData.Tempo:
				fixed_bpm = event.bpm
				return event.bpm
		push_warning("No tempo event found in MIDI data.")
		return 120.0  # Default BPM if not found

## The duration of one beat in seconds.
## Calculated as 60.0 / BPM (beats per minute).
## Used for timing-related calculations in rhythm-based gameplay.
var seconds_per_beat: float:
	get:
		if bpm_fix:
			return 60.0 / fixed_bpm
		elif !_midi_data:
			_load_midi_data()
		for event in _midi_data.tracks[0].events:
			if event is MidiData.Tempo:
				return 60.0 / event.bpm
		push_warning("No tempo event found in MIDI data.")
		return 0.5  # Default seconds per beat if not found

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
		tick += event.delta_time
		if event is MidiData.NoteOn and event.velocity > 0:
			if valid_note_positions.has(event.note):
				var beat_position: float = float(tick) / float(ticks_per_beat)
				note_map[beat_position] = valid_note_positions.find(event.note)
	note_map.sort()
	if note_map.size() == 0:
		push_warning("No valid notes found in track %d with difficulty offset %d." % [track, difficulty_offset])
	return note_map

func _load_midi_data() -> void:
	_midi_data = load(midi_file) as MidiData
	if !_midi_data:
		push_error("Failed to load MIDI data from %s" % midi_file)

func _get_song_track_locations() -> Dictionary[String, int]:
	if !_midi_data:
		_load_midi_data()
	var locations: Dictionary[String, int] = {}
	var cached_names = track_names
	for i in tracks.size():
		var index = cached_names.find(tracks[i].midi_track_name)
		if index != -1:
			locations[tracks[i].midi_track_name] = index
		else:
			push_warning("Track name %s not found in MIDI data." % tracks[i].midi_track_name)
	return locations
