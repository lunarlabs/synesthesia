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

const DIFFICULTY_LEVELS = [96, 102, 108, 114] # MIDI note offsets for Easy, Medium, Hard, Expert

var _midi_data: MidiResource
var _cached_midi_track_names: Array[String] = []

##Path to the MIDI file for this song
@export_file("*.mid") var midi_file:
	set(value):
		if  midi_file != value:
			midi_file = value
			_midi_data = null
			emit_changed()

@export_category("Song Info")

##Short title of the song
@export var title: String = "Unknown Track":
	set(value):
		if  title != value:
			title = value.strip_edges()
			emit_changed()

## Subtitle of the song
@export var sub_title: String = "":
	set(value):
		if  sub_title != value:
			sub_title = value.strip_edges()
			emit_changed()

## Name of the artist or composer
@export var artist: String = "Unknown Artist":
	set(value):
		if  artist != value:
			artist = value.strip_edges()
			emit_changed()

##  Musical genre classification
@export var genre: String = "Unknown Genre":
	set(value):
		if  genre != value:
			genre = value.strip_edges()
			emit_changed()

## The game the song is from
@export var source: String = "":
	set(value):
		if  source != value:
			source = value.strip_edges()
			emit_changed()

@export var cover_art: String = "":
	set(value):
		if  cover_art != value:
			cover_art = value
			emit_changed()

## Description or background information about the song
@export_multiline var description: String:
	set(value):
		if  description != value:
			description = value
			emit_changed()

@export_category("Tracks and Audio")

## Array of SongTrackData resources representing each track in the song
@export var tracks: Array[SongTrackData]

## Path to the audio file for the song's main track
@export_file("*.wav", "*.mp3", "*.ogg") var click_track = "":
	set(value):
		if  click_track != value:
			click_track = value
			emit_changed()

@export_file("*.wav", "*.mp3", "*.ogg") var preview_audio = "":
	set(value):
		if  preview_audio != value:
			preview_audio = value
			emit_changed()

@export_file("*.wav", "*.mp3", "*.ogg") var selection_audio = "":
	set(value):
		if  selection_audio != value:
			selection_audio = value
			emit_changed()

@export_category("Gameplay")

@export_range(0.5, 2.0, 0.1) var scale_fudge_factor: float = 1.0:
	set(value):
		if  scale_fudge_factor != value:
			scale_fudge_factor = value
			emit_changed()

## Number of measures to lead in before gameplay starts
@export_range(0, 500, 1) var lead_in_measures: int = 4:
	set(value):
		if  lead_in_measures != value:
			lead_in_measures = value
			emit_changed()

## Number of playable measures in the song
@export_range(0, 500, 1) var playable_measures: int = 100:
	set(value):
		if  playable_measures != value:
			playable_measures = value
			emit_changed()

## Array of measure indices where checkpoints occur
@export var checkpoints: Array[int]

## Whether to use a fixed BPM value instead of reading from the MIDI file
@export var bpm_fix: bool = false:
	set(value):
		if  bpm_fix != value:
			bpm_fix = value
			emit_changed()

## Fixed BPM value to use if bpm_fix is true
@export var fixed_bpm: float = 120.0:
	set(value):
		if  fixed_bpm != value:
			fixed_bpm = value
			emit_changed()

var _bpm = NAN
var _err = Error.ERR_INVALID_DATA
var _midi_mutex: Mutex = Mutex.new()

var long_title: String:
	get:
		return "%s %s" % [title, sub_title] if not sub_title.is_empty() else title

var midi_error: Error:
	get:
		if not _midi_data:
			_load_midi_data()
		return _err

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
		if _cached_midi_track_names.size() == 0:
			var names: Array[String] = []
			for i in _midi_data.tracks.size():
				for event in _midi_data.tracks[i].events:
					if event["type"] == "meta" and event["subtype"] == 3:
						names.append(event["data"])
						break
			_cached_midi_track_names = names
		if _cached_midi_track_names.size() == 0:
			push_warning("No track names found in MIDI data.")
			printerr("No track names found in MIDI data!")
		return _cached_midi_track_names

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
				return 120.0 # Default BPM if not found
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

func get_file_paths() -> PackedStringArray:
	var result: PackedStringArray
	if resource_path.is_empty():
		push_error("Tried to get file path of unsaved resource.")
		return []
	var song_name = resource_path.get_file()
	result.append(ProjectSettings.globalize_path(resource_path))
	if not FileAccess.file_exists(midi_file):
		push_error(song_name + ": Required midi file missing")
		return []
	result.append(ProjectSettings.globalize_path(midi_file))
	if not FileAccess.file_exists(click_track):
		push_error(resource_path + ": Required audio file missing")
		return []
	result.append(ProjectSettings.globalize_path(click_track))
	for optional_file: String in [preview_audio, selection_audio]:
		if not optional_file.is_empty() and FileAccess.file_exists(optional_file):
			result.append(ProjectSettings.globalize_path(optional_file))
	for track: SongTrackData in tracks:
		if not FileAccess.file_exists(track.audio_file):
			push_error(resource_path + ": Required track audio file missing")
			return []
		result.append(ProjectSettings.globalize_path(track.audio_file))
	return result

## Returns a dictionary mapping timestamps to note values for a specific track and difficulty.
##
## This function retrieves the note mapping for a given track at a specified difficulty level.
## The difficulty offset adjusts which difficulty tier of notes to retrieve.
##
## @param track: The track index to get notes from
## @param difficulty_offset: The offset value to determine the difficulty level
## @return: A Dictionary where keys are timestamps (float) and values are note identifiers (int)
func get_note_map_from_track(track: int, difficulty_offset: int) -> Dictionary[float, int]:
	var time_start = Time.get_ticks_usec()
	var note_map: Dictionary[float, int] = {}
	var tick := 0
	for i in _midi_data.tracks[track].events.size():
		var event = _midi_data.tracks[track].events[i]
		tick += event.delta
		if event.subtype == MIDI_MESSAGE_NOTE_ON and event.data > 0:
			var note_offset: int = event.note - difficulty_offset
			if note_offset == 0 or note_offset == 2 or note_offset == 4:
				var beat_position: float = float(tick) / float(ticks_per_beat)
				@warning_ignore("integer_division")
				var lane_idx = note_offset / 2
				note_map[beat_position] = lane_idx
	note_map.sort()
	if note_map.size() == 0:
		push_warning("No valid notes found in track %d with difficulty offset %d." % [track, difficulty_offset])
	@warning_ignore("integer_division")
	print("Loaded note map %d in %d ms" % [track, (Time.get_ticks_usec() - time_start) / 1000])
	return note_map

func has_difficulty(difficulty_offset: int) -> bool:
	for track in tracks:
		var mdt = _midi_data.tracks[song_track_locations[track.midi_track_name]]
		for event in mdt.events:
			if event.subtype == MIDI_MESSAGE_NOTE_ON and event.data > 0:
				var note_offset: int = event.note - difficulty_offset
				if note_offset == 0 or note_offset == 2 or note_offset == 4:
					return true
	return false

func get_difficulties() -> Array[int]:
	var result: Array[int] = []
	for i in DIFFICULTY_LEVELS:
		if has_difficulty(i):
			result.append(i)
	return result

func _load_midi_data() -> void:
	_midi_mutex.lock()
	if _midi_data:
		_midi_mutex.unlock()
		return
	var time_start = Time.get_ticks_usec()
	var new_midi_data = MidiResource.new()
	var new_err = new_midi_data.load_file(ResourceUID.ensure_path(midi_file))
	assert(new_err == OK)
	if new_err != OK:
		push_error("Failed to load MIDI data from %s" % midi_file)
	_err = new_err
	_midi_data = new_midi_data
	@warning_ignore("integer_division")
	print("Loaded MIDI data in %d ms" % ((Time.get_ticks_usec() - time_start) / 1000))
	_midi_mutex.unlock()

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
	result.set_sync_stream(0, _load_audio_stream(click_track))
	result.set_sync_stream_volume(0, -10.)
	for i in tracks.size():
		result.set_sync_stream(i + 1, _load_audio_stream(tracks[i].audio_file))
		result.set_sync_stream_volume(i + 1, -6.0)
	return result

func _load_audio_stream(path: String) -> AudioStream:
	path = ResourceUID.ensure_path(path)
	var result
	if not FileAccess.file_exists(path):
		push_error("Audio file not found: %s" % path)
		return null
	match path.get_extension():
		"mp3":
			result = AudioStreamMP3.load_from_file(path)
			return result
		"ogg":
			result = AudioStreamOggVorbis.load_from_file(path)
			return result
		_:
			push_error("Unrecognized audio file format: %s" % path)
			return null

func get_cover_art_image() -> Image:
	if cover_art.is_empty():
		return null
	var path = ResourceUID.ensure_path(cover_art)
	if not FileAccess.file_exists(path):
		push_error("Cover art file not found: %s" % path)
		return null
	var image = Image.new()
	var err = image.load(path)
	if err != OK:
		push_error("Failed to load cover art image: %s" % path)
		return null
	return image
