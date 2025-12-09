extends Node
## Test harness for preprocessing MIDI tracks of a SongData.
## Loads a SongData (baseline) and runs SynRoadTrackPreprocessor for Beginner difficulty (offset 96).
## Prints per-track note counts, phrase counts, and longest phrase length.

const SONG_DATA_PATH := "res://song/baseline/baseline.tres"
const DIFFICULTY_OFFSET_BEGINNER := 96

var _preprocessor: SynRoadTrackPreprocessor
var _midi_data: MidiData
var _ticks_per_beat: int
var _song: SongData

func _ready():
	print("[SongPreprocessTest] Loading song data: ", SONG_DATA_PATH)
	_song = load(SONG_DATA_PATH) as SongData
	if !_song:
		push_error("Failed to load SongData at " + SONG_DATA_PATH)
		return
	_midi_data = load(_song.midi_file) as MidiData
	if !_midi_data:
		push_error("Failed to load MidiData from SongData.midi_file: " + str(_song.midi_file))
		return
	_ticks_per_beat = _midi_data.header.ticks_per_beat
	print("Ticks per beat: ", _ticks_per_beat)
	print("Track names discovered (SongData.track_names): ", _song.track_names)
	_run_preprocess()
	print("Press SPACE to rerun preprocessing.")

func _run_preprocess():
	_preprocessor = SynRoadTrackPreprocessor.new()
	# Queue every MIDI track. Use track name if available else fallback to index label.
	var names: Array[String] = _song.track_names
	for i in _midi_data.tracks.size():
		var label = names[i] if i < names.size() else "<unnamed %d>" % i
#		_preprocessor.queue_job(i, _midi_data, _ticks_per_beat, DIFFICULTY_OFFSET_BEGINNER)
	_preprocessor.wait_for_all()
	var results = _preprocessor.take_completed()
	_print_results(results)

func _print_results(results: Array):
	print("=== Preprocess Summary (difficulty offset %d) ===" % DIFFICULTY_OFFSET_BEGINNER)
	for r in results:
		var idx: int = r.track_index
		var data: Dictionary = r.result
		var note_map: Dictionary = data.note_map
		var phrases: Array = data.phrases
		var longest_phrase: int = 0
		for p in phrases:
			longest_phrase = max(longest_phrase, p.score_value)
		var track_label = _song.track_names[idx] if idx < _song.track_names.size() else "Track %d" % idx
		print("Track %d | %s -> notes: %d, phrases: %d, longest phrase: %d" % [idx, track_label, note_map.size(), phrases.size(), longest_phrase])
	print("===============================================")

func _input(event):
	if event.is_action_pressed("ui_accept"):
		print("[SongPreprocessTest] Rerunning preprocessing...")
		_run_preprocess()
