extends Node

var _song_catalog: Array[SongEntry] = []
var _mutex: Mutex = Mutex.new()
var _preprocessor: SynRoadCatalogPreprocessor = SynRoadCatalogPreprocessor.new()
var _async_reload_in_progress: bool = false
var _loaded_data: Array = []

const CATALOG_JSON_PATH = "user://song_catalog.json"
const SONG_DIRECTORY_PATH = "res://song/"
const DIFFICULTY_LEVELS = [96, 102, 108, 114]  # MIDI note offsets for Easy, Medium, Hard, Expert
const DIFFICULTY_NAMES = {
	96: "Easy",
	102: "Medium",
	108: "Hard",
	114: "Expert"
}
const INSTRUMENT_NAMES = [
	"drums",
	"bass",
	"guitar",
	"synth",
	"vocals",
	"fx",
]

var is_initialized: bool:
	get:
		return _song_catalog.size() > 0
var catalog:
	get:
		return _song_catalog

# Represents a single song entry in the catalog.
class SongEntry:
	var file_path: String
	var title: String
	var long_title: String
	var artist: String
	var genre: String
	var bpm: float
	var available_difficulties: Array
	var instruments: PackedStringArray
	var note_counts: Dictionary[int, int]
	var difficulty_ratings: Dictionary[int, int]
	var detailed_difficulty_info: Dictionary[int, DetailedDifficultyInfo]
	var files_valid: bool
	var error_message: String = ""

# For each difficulty in each song, detailed info. Array index is instrument track index.
class DetailedDifficultyInfo:
	var track_note_counts: PackedInt32Array
	var measure_note_counts: Array[PackedInt32Array]
	var phrase_raw_difficulties: Array[PackedFloat32Array]
	var track_avg_raw_difficulties: PackedFloat32Array
	var avg_raw_difficulty: float

static func _to_json(entry: SongEntry) -> Dictionary:
	var dict := {
		"file_path": entry.file_path,
		"title": entry.title,
		"long_title": entry.long_title,
		"artist": entry.artist,
		"genre": entry.genre,
		"bpm": entry.bpm,
		"available_difficulties": entry.available_difficulties,
		"note_counts": entry.note_counts,
		"difficulty_ratings": entry.difficulty_ratings,
		"files_valid": entry.files_valid,
		"error_message": entry.error_message
	}
	return dict

static func _from_json(dict: Dictionary) -> SongEntry:
	var entry = SongEntry.new()
	entry.file_path = dict.get("file_path", "")
	# Handle both old format (nested song_data) and new format (flat)
	if dict.has("song_data"):
		var song_data_dict = dict.get("song_data", {})
		entry.title = song_data_dict.get("title", "")
		entry.artist = song_data_dict.get("artist", "")
		entry.genre = song_data_dict.get("genre", "")
	else:
		entry.title = dict.get("title", "")
		entry.long_title = dict.get("long_title", entry.title)
		entry.artist = dict.get("artist", "")
		entry.genre = dict.get("genre", "")
	entry.bpm = dict.get("bpm", 120.0)
	entry.available_difficulties = dict.get("available_difficulties", [])
	entry.note_counts = dict.get("note_counts", {})
	entry.note_densities = dict.get("note_densities", {})
	entry.difficulty_ratings = dict.get("difficulty_ratings", {})
	entry.files_valid = dict.get("files_valid", false)
	entry.error_message = dict.get("error_message", "")
	# convert keys to int if necessary
	for diff in entry.available_difficulties:
		if typeof(diff) != TYPE_INT:
			entry.available_difficulties[entry.available_difficulties.find(diff)] = int(diff)
	for i in entry.note_counts.keys():
		if typeof(i) != TYPE_INT:
			var val = entry.note_counts[i]
			entry.note_counts.erase(i)
			entry.note_counts[int(i)] = int(val)
	for i in entry.note_densities.keys():
		if typeof(i) != TYPE_INT:
			var val = entry.note_densities[i]
			entry.note_densities.erase(i)
			entry.note_densities[int(i)] = int(val)
	for i in entry.difficulty_ratings.keys():
		if typeof(i) != TYPE_INT:
			var val = entry.difficulty_ratings[i]
			entry.difficulty_ratings.erase(i)
			entry.difficulty_ratings[int(i)] = int(val)

	return entry

func save_to_json(path: String) -> Error:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Failed to open file for writing: %s" % path)
		return file.get_error()
	var entries_array := []
	for entry in _song_catalog:
		entries_array.append(_to_json(entry))
	var json_dict := {"song_catalog": entries_array}
	var json_text = JSON.stringify(json_dict, "\t")
	file.store_string(json_text)
	file.close()
	return OK

func load_from_json(path: String) -> Error:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Failed to open file for reading: %s" % path)
		return file.get_error()
	var json_text = file.get_as_text()
	file.close()
	var json = JSON.new()
	var error = json.parse(json_text)
	if error == OK:
		var data = json.data
		var entries_array = data.get("song_catalog", [])
		_song_catalog.clear()
		for entry_dict in entries_array:
			var entry = _from_json(entry_dict)
			_song_catalog.append(entry)
		return OK
	else:
		push_error("Error when loading JSON from file %s: %s" % [path, json.get_error_message()])
		return error

func get_song_catalog() -> Array[SongEntry]:
	if _song_catalog.size() == 0:
		_song_catalog = _scan_for_songs()
	return _song_catalog

func clear_catalog() -> void:
	_song_catalog.clear()

func reload_song_catalog() -> void:
	pass  # Deprecated: use start_reload_async() and await_catalog_ready() instead

# Starts an async reload: queues jobs and returns immediately
func start_reload_async() -> void:
	if _async_reload_in_progress:
		return
	_async_reload_in_progress = true
	_scan_for_songs_async()

# Await until preprocessing finishes, then apply results and return catalog
func await_catalog_ready() -> Array[SongEntry]:
	while _preprocessor.running:
		await Engine.get_main_loop().process_frame
	var results = _preprocessor.take_completed()
	var entries = _apply_preprocessor_results(results)
	_async_reload_in_progress = false
	_song_catalog = entries
	_song_catalog.sort_custom(func(a, b): return a.title < b.title)
	return _song_catalog

func _scan_for_songs():
	print("Obsolete synchronous song scan called; use async variant instead.")
	_loaded_data = []
	var dir = DirAccess.open(SONG_DIRECTORY_PATH)
	if not dir:
		push_error("Failed to open song directory.")
		return

	dir.list_dir_begin()
	var folder_name = dir.get_next()

	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			print("Found song folder: %s" % folder_name)
			var song_resource_path = SONG_DIRECTORY_PATH + folder_name + "/" + folder_name + ".tres"
			if FileAccess.file_exists(song_resource_path):
				var song_data = ResourceLoader.load(song_resource_path) as SongData
				if song_data:
					var midi_data = song_data.midi_data
					if not midi_data:
						print("Failed to load MIDI data for song: %s" % song_resource_path)
					else:
						_loaded_data.append([folder_name, song_data, midi_data])
						print("Queued song for preprocessing: %s" % song_resource_path)
				else:
					print("Failed to load SongData resource at: %s" % song_resource_path)
			else:
				print("No resource file found at expected path: %s" % song_resource_path)
				push_warning("Missing resource file for song in folder: %s" % folder_name)
		folder_name = dir.get_next()

	dir.list_dir_end()
	_song_catalog = []
	_song_catalog.resize(_loaded_data.size())
	var task_id = WorkerThreadPool.add_group_task(_process_song_data, _loaded_data.size())
	print("Waiting for %d song processing tasks to complete..." % _loaded_data.size())
	WorkerThreadPool.wait_for_group_task_completion(task_id)
	return
	# var song_entries: Array[SongEntry] = []
	# var song_dir := "res://song/"
	# var dir = DirAccess.open(song_dir)
	# if not dir:
	# 	push_error("Failed to open song directory.")
	# 	return song_entries

	# dir.list_dir_begin()
	# var folder_name = dir.get_next()

	# while folder_name != "":
	# 	if dir.current_is_dir() and not folder_name.begins_with("."):
	# 		print("Found song folder: %s" % folder_name)
	# 		var song_resource_path = song_dir + folder_name + "/" + folder_name + ".tres"
	# 		if FileAccess.file_exists(song_resource_path):
	# 			_preprocessor.queue_job(song_resource_path)
	# 		else:
	# 			print("No resource file found at expected path: %s" % song_resource_path)
	# 			push_warning("Missing resource file for song in folder: %s" % folder_name)
	# 	folder_name = dir.get_next()
	
	# dir.list_dir_end()
	# _preprocessor.wait_for_all()
	# var results = _preprocessor.take_completed()
	# song_entries = _apply_preprocessor_results(results)

	# song_entries.sort_custom(func(a, b): return a.song_data.title < b.song_data.title)

	# return song_entries

func _process_song_data(entry_idx: int):
	var result := SongEntry.new()
	var loaded = _loaded_data[entry_idx]
	var folder_name: String = loaded[0]
	var song_data: SongData = loaded[1]
	var midi_data: MidiData = loaded[2]
	song_data._midi_data = midi_data  # Ensure MIDI data is set

	result.file_path = "res://song/%s/%s.tres" % [folder_name, folder_name]
	result.title = song_data.title
	result.long_title = song_data.long_title
	result.artist = song_data.artist
	result.genre = song_data.genre
	result.bpm = song_data.bpm

	var midi_track_indices = song_data.song_track_locations.values()
	var difficulty_maps := {}
	for i in DIFFICULTY_LEVELS:
		var track_map: Array[Dictionary] = []
		var total_note_count := 0
		for track_idx in midi_track_indices:
			var note_map = song_data.get_note_map_from_track(track_idx, i)
			total_note_count += note_map.size()
			track_map.append(note_map)
		if total_note_count > 0:
			difficulty_maps[i] = track_map
	
	var detailed_diffs_info: Dictionary[int, DetailedDifficultyInfo] = {}

# Async variant: queues jobs and returns immediately; call await_catalog_ready() to finish
func _scan_for_songs_async() -> void:
	var song_dir := "res://song/"
	var dir = DirAccess.open(song_dir)
	if not dir:
		return
	dir.list_dir_begin()
	var folder_name = dir.get_next()
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			var song_resource_path = song_dir + folder_name + "/" + folder_name + ".tres"
			if FileAccess.file_exists(song_resource_path):
				print("Queueing song for preprocessing: %s" % song_resource_path)
				_preprocessor.queue_job(song_resource_path)
		folder_name = dir.get_next()
	dir.list_dir_end()

func _apply_preprocessor_results(results: Array) -> Array[SongEntry]:
	print("Taking %d completed preprocessor results" % results.size())
	var entries: Array[SongEntry] = []
	for result in results:
		print("Processing result: %s" % str(result))
		var song_resource_path: String = result.get("song_resource_path", "")
		if song_resource_path == "":
			print("  Skipping: no song_resource_path")
			continue
		
		var entry = SongEntry.new()
		var result_data = result.get("result", {})
		if not result_data.get("success", false):
			print("  Failed: %s" % result_data.get("error_message", "Unknown error"))
			entry.files_valid = false
			entry.error_message = result_data.get("error_message", "Unknown error during preprocessing.")
			continue
		entry.file_path = song_resource_path
		var song_data = ResourceLoader.load(song_resource_path) as SongData
		if not song_data:
			print("  Failed to load SongData resource")
			entry.files_valid = false
			entry.error_message = "Failed to load song data resource."
			continue
		if song_data.click_track == null:
			print("  Failed: missing click track")
			entry.files_valid = false
			entry.error_message = "Missing click track in song data."
			continue
		entry.title = song_data.title
		entry.long_title = song_data.long_title
		entry.artist = song_data.artist
		entry.genre = song_data.genre
		entry.bpm = result_data.get("bpm", 120.0)
		var available_diffs: Array[int] = []
		var note_counts_dict: Dictionary[int, int] = {}
		var note_densities_dict: Dictionary[int, float] = {}
		var difficulty_ratings_dict: Dictionary[int, int] = {}
		var difficulties: Dictionary = result_data.get("difficulties", {})
		for diff_key in difficulties.keys():
			available_diffs.append(int(diff_key))
			var diff_info: Dictionary = difficulties[diff_key]
			note_counts_dict[int(diff_key)] = diff_info.get("note_count", 0)
			note_densities_dict[int(diff_key)] = diff_info.get("average_density", -1.0)
			difficulty_ratings_dict[int(diff_key)] = diff_info.get("difficulty_rating", 0)
		entry.available_difficulties = available_diffs
		entry.note_counts = note_counts_dict
		entry.note_densities = note_densities_dict
		entry.difficulty_ratings = difficulty_ratings_dict
		entry.files_valid = true
		print("  Success: %s with difficulties %s" % [entry.title, entry.available_difficulties])
		entries.append(entry)
	print("Returning %d entries" % entries.size())
	_song_catalog = entries
	return entries

# Scans all tracks once and returns data for all difficulties
func _scan_all_difficulties(song_data: SongData) -> Dictionary:
	if not song_data._midi_data:
		song_data._load_midi_data()
	
	# Initialize storage for each difficulty
	var diff_data := {}
	for diff in [96, 102, 108, 114]:
		diff_data[diff] = {"note_count": 0, "beat_positions": []}
	
	# Scan each track once, collecting data for all difficulties
	for track_data in song_data.tracks:
		var track_idx = song_data.track_names.find(track_data.midi_track_name)
		if track_idx < 0:
			continue
		
		var tick := 0
		for event in song_data._midi_data.tracks[track_idx].events:
			tick += event.delta_time
			if event is MidiData.NoteOn and event.velocity > 0:
				var beat_position: float = float(tick) / float(song_data.ticks_per_beat)
				
				# Check which difficulty this note belongs to
				for diff in [96, 102, 108, 114]:
					if event.note == diff or event.note == diff + 2 or event.note == diff + 4:
						diff_data[diff].note_count += 1
						diff_data[diff].beat_positions.append(beat_position)
						break
	
	# Calculate average phrase densities for each difficulty
	for diff in [96, 102, 108, 114]:
		if diff_data[diff].note_count > 0:
			diff_data[diff].average_density = _calculate_density_from_beats(
				diff_data[diff].beat_positions,
				song_data.lead_in_measures,
				song_data.playable_measures
			)
		else:
			diff_data[diff].average_density = -1.0
	
	return diff_data

func _calculate_density_from_beats(beat_positions: Array, lead_in_measures: int, playable_measures: int) -> float:
	if beat_positions.size() == 0:
		return -1.0
	
	var total_measures = playable_measures + lead_in_measures
	var phrase_note_sum := 0
	var num_phrases = playable_measures - 1
	
	for i in range(lead_in_measures, total_measures - 1):
		# Count notes in this 2-measure phrase (rolling window)
		var count = beat_positions.filter(func(beat): 
			var measure = floori(beat / 4.0)
			return measure == i or measure == i + 1
		).size()
		phrase_note_sum += count
	
	return float(phrase_note_sum) / float(num_phrases) if num_phrases > 0 else 0.0
				
