extends Node

var _song_catalog: Array[SongEntry] = []
var _loaded_data: Array = []

const CATALOG_JSON_PATH = "user://song_catalog.json"
const DIFFICULTY_DETAILS_JSON_PATH = "user://song_difficulty_details.json"
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
const EPSILON = 0.001 # because floating point
const QUANT_FACTOR_QUARTER = 1.0
const QUANT_FACTOR_EIGHTH = 1.1
const QUANT_FACTOR_SIXTEENTH = 1.3
const QUANT_FACTOR_THIRTY_SECOND = 1.5
const BASE_SPEED_WEIGHT = 1.0
const JACK_SPEED_THRESHOLD = 0.2  # seconds between notes to consider "jacking"
const PATTERN_WEIGHT_JACK = 2.5   # Penalty for fast repeated notes
const PATTERN_WEIGHT_JUMP = 1.5   # Penalty for Lane 0 -> Lane 2
const PATTERN_WEIGHT_EASY = 0.8   # Bonus for slow repeated notes
const ARTICLE_LIST = ["a ", "an ", "the "]

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
	var note_densities: Dictionary[int, float]
	var difficulty_ratings: Dictionary[int, float]
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

static func _entry_to_json(entry: SongEntry) -> Dictionary:
	var dict := {
		"file_path": entry.file_path,
		"title": entry.title,
		"long_title": entry.long_title,
		"artist": entry.artist,
		"genre": entry.genre,
		"bpm": entry.bpm,
		"instruments": Array(entry.instruments),
		"available_difficulties": entry.available_difficulties,
		"note_counts": {},
		"note_densities": {},
		"difficulty_ratings": {},
		"files_valid": entry.files_valid,
		"error_message": entry.error_message
	}

	for diff in entry.note_counts.keys():
		dict["note_counts"][str(diff)] = entry.note_counts[diff]

	for diff in entry.note_densities.keys():
		dict["note_densities"][str(diff)] = entry.note_densities[diff]

	for diff in entry.difficulty_ratings.keys():
		dict["difficulty_ratings"][str(diff)] = entry.difficulty_ratings[diff]

	return dict

static func _difficulty_info_to_json(ddi: DetailedDifficultyInfo) -> Dictionary:
	assert(ddi.track_note_counts.size() > 0)
	assert(ddi.track_avg_raw_difficulties.size() == ddi.track_note_counts.size())

	var dict := {
		"track_note_counts": Array(ddi.track_note_counts),
		"measure_note_counts": [],
		"phrase_raw_difficulties": [],
		"track_avg_raw_difficulties": Array(ddi.track_avg_raw_difficulties),
		"avg_raw_difficulty": ddi.avg_raw_difficulty
	}

	for i in range(ddi.measure_note_counts.size()):
		dict["measure_note_counts"].append(
			Array(ddi.measure_note_counts[i])
		)

	for i in range(ddi.phrase_raw_difficulties.size()):
		dict["phrase_raw_difficulties"].append(
			Array(ddi.phrase_raw_difficulties[i])
		)

	return dict

static func _entry_from_json(dict: Dictionary) -> SongEntry:
	var entry := SongEntry.new()

	entry.file_path = dict.get("file_path", "")
	entry.title = dict.get("title", "")
	entry.long_title = dict.get("long_title", "")
	entry.artist = dict.get("artist", "")
	entry.genre = dict.get("genre", "")
	entry.bpm = dict.get("bpm", 0.0)
	entry.instruments = dict.get("instruments", [])
	entry.available_difficulties = dict.get("available_difficulties", [])

	entry.note_counts = {}
	entry.note_densities = {}
	entry.difficulty_ratings = {}

	entry.files_valid = dict.get("files_valid", false)
	entry.error_message = dict.get("error_message", "")

	var nc = dict.get("note_counts", {})
	for diff_str in nc.keys():
		entry.note_counts[int(diff_str)] = int(nc[diff_str])

	var nd = dict.get("note_densities", {})
	for diff_str in nd.keys():
		entry.note_densities[int(diff_str)] = float(nd[diff_str])

	var dr = dict.get("difficulty_ratings", {})
	for diff_str in dr.keys():
		entry.difficulty_ratings[int(diff_str)] = dr[diff_str]

	return entry

static func _difficulty_info_from_json(dict: Dictionary) -> DetailedDifficultyInfo:
	var ddi := DetailedDifficultyInfo.new()

	# Track note counts
	var tnc := PackedInt32Array()
	for v in dict.get("track_note_counts", []):
		tnc.append(int(v))
	ddi.track_note_counts = tnc

	# Measure note counts
	ddi.measure_note_counts = []
	for measure_array in dict.get("measure_note_counts", []):
		var packed := PackedInt32Array()
		for v in measure_array:
			packed.append(int(v))
		ddi.measure_note_counts.append(packed)

	# Phrase raw difficulties
	ddi.phrase_raw_difficulties = []
	for phrase_array in dict.get("phrase_raw_difficulties", []):
		var packed := PackedFloat32Array()
		for v in phrase_array:
			packed.append(float(v))
		ddi.phrase_raw_difficulties.append(packed)

	# Track average raw difficulties
	var tard := PackedFloat32Array()
	for v in dict.get("track_avg_raw_difficulties", []):
		tard.append(float(v))
	ddi.track_avg_raw_difficulties = tard

	# Overall average
	ddi.avg_raw_difficulty = float(dict.get("avg_raw_difficulty", 0.0))

	return ddi

func save_entries_to_json() -> Error:
	var file := FileAccess.open(CATALOG_JSON_PATH, FileAccess.WRITE)
	if file == null:
		var err := FileAccess.get_open_error()
		push_error("Failed to open file for writing: %s (err %d)" % [CATALOG_JSON_PATH, err])
		return err

	var entries_array: Array = []

	# Explicitly handle catalog type
	for entry in _song_catalog:
		entries_array.append(_entry_to_json(entry))

	var json_dict := {
		"song_catalog": entries_array
	}

	var json_text := JSON.stringify(json_dict, "\t")
	file.store_string(json_text)
	file.close()

	return OK

func save_difficulty_details_to_json() -> Error:
	var file := FileAccess.open(DIFFICULTY_DETAILS_JSON_PATH, FileAccess.WRITE)
	if file == null:
		var err := FileAccess.get_open_error()
		push_error("Failed to open file for writing: %s (err %d)" % [DIFFICULTY_DETAILS_JSON_PATH, err])
		return err

	var details_dict: Dictionary = {}

	for entry in _song_catalog:
		var diff_details: Dictionary = {}

		for diff in entry.detailed_difficulty_info.keys():
			diff_details[str(diff)] = _difficulty_info_to_json(
				entry.detailed_difficulty_info[diff]
			)

		# file_path used as stable song identifier
		details_dict[entry.file_path] = diff_details

	var json_text := JSON.stringify(details_dict, "\t")
	file.store_string(json_text)
	file.close()

	return OK

func load_entries_from_json() -> Error:
	if not FileAccess.file_exists(CATALOG_JSON_PATH):
		push_error("Song catalog JSON not found: %s" % CATALOG_JSON_PATH)
		return ERR_FILE_NOT_FOUND

	var file := FileAccess.open(CATALOG_JSON_PATH, FileAccess.READ)
	if file == null:
		var err := FileAccess.get_open_error()
		push_error("Failed to open song catalog JSON: %s (err %d)" % [CATALOG_JSON_PATH, err])
		return err

	var json_text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid song catalog JSON format")
		return ERR_PARSE_ERROR

	var catalog_array = parsed.get("song_catalog", [])
	if typeof(catalog_array) != TYPE_ARRAY:
		push_error("song_catalog is not an array")
		return ERR_PARSE_ERROR

	_song_catalog.clear()

	for entry_dict in catalog_array:
		if typeof(entry_dict) != TYPE_DICTIONARY:
			continue

		var entry := _entry_from_json(entry_dict)
		_song_catalog.append(entry)

	_song_catalog.sort_custom(_compare_song_titles)
	return OK

func load_difficulty_details_from_json() -> Error:
	if not FileAccess.file_exists(DIFFICULTY_DETAILS_JSON_PATH):
		push_error("Difficulty details JSON not found: %s" % DIFFICULTY_DETAILS_JSON_PATH)
		return ERR_FILE_NOT_FOUND

	var file := FileAccess.open(DIFFICULTY_DETAILS_JSON_PATH, FileAccess.READ)
	if file == null:
		var err := FileAccess.get_open_error()
		push_error("Failed to open difficulty details JSON: %s (err %d)" % [DIFFICULTY_DETAILS_JSON_PATH, err])
		return err

	var json_text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid difficulty details JSON format")
		return ERR_PARSE_ERROR

	# Build lookup table by file_path
	var entry_by_path: Dictionary = {}
	for entry in _song_catalog:
		entry_by_path[entry.file_path] = entry
		entry.detailed_difficulty_info.clear()

	# Attach difficulty info
	for file_path in parsed.keys():
		if not entry_by_path.has(file_path):
			push_warning("Difficulty data for unknown song: %s" % file_path)
			continue

		var entry: SongEntry = entry_by_path[file_path]
		var diff_dict = parsed[file_path]

		if typeof(diff_dict) != TYPE_DICTIONARY:
			continue

		for diff_str in diff_dict.keys():
			var diff := int(diff_str)
			var ddi_dict = diff_dict[diff_str]

			if typeof(ddi_dict) != TYPE_DICTIONARY:
				continue

			var ddi := _difficulty_info_from_json(ddi_dict)
			entry.detailed_difficulty_info[diff] = ddi

	return OK

func scan_for_songs():
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
				print("Loading SongData from: %s" % song_resource_path)
				if song_data:
					var midi_data = song_data.midi_data
					print("Loading MIDI data for song: %s" % song_resource_path)
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
	_song_catalog.sort_custom(_compare_song_titles)
	return

func _process_song_data(entry_idx: int):
	var result := SongEntry.new()
	var loaded = _loaded_data[entry_idx]
	var folder_name: String = loaded[0]
	var song_data: SongData = loaded[1]
	var midi_data: MidiData = loaded[2]
	print("Processing song: %s" % folder_name)
	song_data._midi_data = midi_data  # Ensure MIDI data is set

	result.file_path = "res://song/%s/%s.tres" % [folder_name, folder_name]
	result.title = song_data.title
	result.long_title = song_data.long_title
	result.artist = song_data.artist
	result.genre = song_data.genre
	result.bpm = song_data.bpm
	var instruments: Array[String]
	var track_count = song_data.tracks.size()
	for i in track_count:
		instruments.append(INSTRUMENT_NAMES[song_data.tracks[i].instrument])
	result.instruments = PackedStringArray(instruments)
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
			result.note_counts[i] = total_note_count
			result.note_densities[i] = float(total_note_count) / float(song_data.total_measures)
	result.available_difficulties = difficulty_maps.keys()

	var detailed_diffs_info: Dictionary[int, DetailedDifficultyInfo] = {}
	for diff in difficulty_maps.keys():
		var ddi := DetailedDifficultyInfo.new()
		ddi.track_note_counts.resize(track_count)
		ddi.measure_note_counts.resize(track_count)
		ddi.phrase_raw_difficulties.resize(track_count)
		ddi.track_avg_raw_difficulties.resize(track_count)
		for i in range(track_count):
			var note_map = difficulty_maps[diff][i]
			ddi.track_note_counts[i] = note_map.size()
			var sorted_keys = note_map.keys()
			sorted_keys.sort()
			var measure_counts: PackedInt32Array = PackedInt32Array()
			measure_counts.resize(song_data.total_measures)
			for beat_pos in sorted_keys:
				var measure_idx = int(floor(beat_pos / 4.0))
				if measure_idx >= 0 and measure_idx < song_data.total_measures:
					measure_counts[measure_idx] += 1
			ddi.measure_note_counts[i] = measure_counts
			var phrase_difficulties: PackedFloat32Array = PackedFloat32Array()
			phrase_difficulties.resize(song_data.total_measures)
			var track_raw_difficulty := 0.0
			var phrase_map = _build_phrase_map_single_pass(note_map.keys())
			for start_measure in phrase_map.keys():
				if start_measure >= phrase_difficulties.size():
					break
				var note_indices = phrase_map[start_measure]
				var raw_difficulty = _calculate_phrase_difficulty(
					note_map,
					sorted_keys,
					note_indices,
					song_data.seconds_per_beat)
				phrase_difficulties[start_measure] = raw_difficulty
				track_raw_difficulty += raw_difficulty
			ddi.phrase_raw_difficulties[i] = phrase_difficulties
			ddi.track_avg_raw_difficulties[i] = track_raw_difficulty / float(max(phrase_map.size(), 1))
		# Average across all tracks
		var total_avg := 0.0
		for i in range(track_count):
			total_avg += ddi.track_avg_raw_difficulties[i]
		ddi.avg_raw_difficulty = total_avg / float(track_count)
		result.difficulty_ratings[diff] = ddi.avg_raw_difficulty
		detailed_diffs_info[diff] = ddi
	
	result.detailed_difficulty_info = detailed_diffs_info
	result.files_valid = true
	print("Finished processing song: %s" % folder_name)
	_song_catalog[entry_idx] = result

func _calculate_phrase_difficulty(
	note_map: Dictionary, # Kept for looking up lanes
	sorted_beats: Array,  # NEW: The sorted time keys
	note_indices: PackedInt32Array,
	seconds_per_beat: float) -> float:
	
	var total_strain := 0.0
	
	if note_indices.size() > 1:
		# Loop starting from the second note in the phrase
		for i in range(1, note_indices.size()):
			var idx_current = note_indices[i]
			var idx_prev = note_indices[i - 1]
			
			var beat_a = sorted_beats[idx_prev]
			var beat_b = sorted_beats[idx_current]
			
			var interval = beat_b - beat_a
			if interval <= 0.001: 
				interval = 0.001 # Clamp to avoid division by zero
			
			var time_interval = interval * seconds_per_beat
			
			# 1. Speed Strain: Penalize density
			var speed_strain = 1.0 / max(time_interval, 0.05) 

			# 2. Quantization: Check the beat timestamp (beat_b), not the interval
			var quant_modifier = _get_beat_quantization_factor(beat_b)

			# 3. Pattern: Check lanes
			var pattern_modifier = _get_pattern_weight(
				note_map[beat_a], # Look up lane in dictionary
				note_map[beat_b],
				time_interval)
			
			var note_strain = speed_strain * quant_modifier * pattern_modifier
			total_strain += note_strain
			
		total_strain /= float(note_indices.size() - 1)
	else:
		total_strain = 0.0
		
	return total_strain

func _build_phrase_map_single_pass(sorted_beats: Array) -> Dictionary[int, PackedInt32Array]:
	var phrase_map: Dictionary[int, PackedInt32Array] = {}
	var active_phrases: Dictionary[int, PackedInt32Array] = {}

	for j in range(sorted_beats.size()):
		var beat_pos = sorted_beats[j]
		var measure_idx := int(floor(beat_pos / 4.0))

		# 1. Start phrase at this measure if it doesn't exist
		if not phrase_map.has(measure_idx):
			var phrase := PackedInt32Array()
			phrase_map[measure_idx] = phrase
			active_phrases[measure_idx] = phrase

		# 2. Append this note to all active phrases (Sliding Window logic)
		# Note: We iterate a copy of keys to safely modify the dictionary while iterating
		for start_measure in active_phrases.keys():
			if measure_idx < start_measure + 2: # 2-measure window
				active_phrases[start_measure].append(j)
			else:
				active_phrases.erase(start_measure)

	return phrase_map

func _get_beat_quantization_factor(beat: float) -> float:
	if abs(fmod(beat, 1.0)) < EPSILON:
		return QUANT_FACTOR_QUARTER
	elif abs(fmod(beat, 0.5)) < EPSILON:
		return QUANT_FACTOR_EIGHTH
	elif abs(fmod(beat, 0.25)) < EPSILON:
		return QUANT_FACTOR_SIXTEENTH
	else:
		return QUANT_FACTOR_THIRTY_SECOND

func _get_pattern_weight(
	prev_lane: int,
	curr_lane: int,
	time_interval: float) -> float:
	var lane_change = abs(curr_lane - prev_lane)
	match lane_change:
		0:
			if time_interval < JACK_SPEED_THRESHOLD:
				return PATTERN_WEIGHT_JACK
			else:
				return PATTERN_WEIGHT_EASY
		1:
			return 1.0  # Neutral weight for single lane changes
		2:
			return PATTERN_WEIGHT_JUMP
		_:
			return 1.0  # Fallback neutral weight

func _compare_song_titles(a: SongEntry, b: SongEntry) -> bool:
	var title_a = _strip_leading_articles(a.title)
	var title_b = _strip_leading_articles(b.title)
	return title_a < title_b

func _strip_leading_articles(text: String) -> String:
	text = text.strip_edges()
	var lower_name = text.to_lower()
	for article in ARTICLE_LIST:
		if lower_name.begins_with(article):
			return text.substr(article.length(), text.length() - article.length())
	return text
