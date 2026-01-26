extends Node

var _song_catalog: Array[SongEntry] = []
var _loaded_data: Array = []
var additions: Array = []

const CATALOG_JSON_PATH = "user://song_catalog.json"
const DIFFICULTY_DETAILS_JSON_PATH = "user://song_difficulty_details.json"
const SONG_DIRECTORY_PATH = "res://song/"
const DIFFICULTY_LEVELS = [96, 102, 108, 114] # MIDI note offsets for Easy, Medium, Hard, Expert
const DIFFICULTY_NAMES = {
	96: "Beginner",
	102: "Basic",
	108: "Advanced",
	114: "Expert",
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
const JACK_SPEED_THRESHOLD = 0.2 # seconds between notes to consider "jacking"
const PATTERN_WEIGHT_JACK = 2.5 # Penalty for fast repeated notes
const PATTERN_WEIGHT_JUMP = 1.5 # Penalty for Lane 0 -> Lane 2
const PATTERN_WEIGHT_EASY = 0.8 # Bonus for slow repeated notes

#region Query Constants
const BASE_QUERY = """SELECT 
	folder_id, 
	title, 
	sub_title, 
	artist, 
	genre, 
	bpm, 
	available_difficulties, 
	source_name, 
	files_ok, 
	resource_hash,
	midi_hash
FROM v_song_select"""

const DIFFICULTY_QUERY = """SELECT 
	folder_id, 
	title, 
	sub_title, 
	artist, 
	genre, 
	bpm, 
	difficulty_offset,
	difficulty_rating, 
	source_name, 
	files_ok, 
	resource_hash,
	midi_hash
FROM v_full_library"""

const DEFAULT_ORDER_BY = "ORDER BY sort_key ASC;"
const BPM_ORDER_BY = "ORDER BY bpm ASC;"
const DIFF_RATING_ORDER_BY = "ORDER BY difficulty_rating DESC;"
#endregion

var is_initialized: bool:
	get:
		return _song_catalog.size() > 0
var catalog:
	get:
		return _song_catalog

# Represents a single song entry in the catalog.
# To be obsoleted by the database.
class SongEntry:
	var folder: String
	var file_path: String
	var title: String
	var sub_title: String
	var artist: String
	var genre: String
	var source: String
	var bpm: float
	var available_difficulties: Array
	var instruments: PackedStringArray
	var note_counts: Dictionary[int, int]
	var note_densities: Dictionary[int, float]
	var difficulty_ratings: Dictionary[int, float]
	var detailed_difficulty_info: Dictionary[int, DetailedDifficultyInfo]
	var files_valid: bool

# For each difficulty in each song, detailed info. Array index is instrument track index.
class DetailedDifficultyInfo:
	var track_note_counts: PackedInt32Array
	var measure_note_counts: Array[PackedInt32Array]
	var phrase_raw_difficulties: Array[PackedFloat32Array]
	var track_avg_raw_difficulties: PackedFloat32Array
	var avg_raw_difficulty: float

# TODO: function to get song details from database
# as well as sorting and filtering

# To be obsoleted by the database.
static func _entry_to_json(entry: SongEntry) -> Dictionary:
	var dict := {
		"folder": entry.folder,
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

# To be obsoleted by the database.
func _difficulty_info_to_json(ddi: DetailedDifficultyInfo) -> Dictionary:
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

# To be obsoleted by the database.
static func _entry_from_json(dict: Dictionary) -> SongEntry:
	var entry := SongEntry.new()

	entry.folder = dict.get("folder", "")
	entry.file_path = dict.get("file_path", "")
	entry.title = dict.get("title", "")
	entry.long_title = dict.get("long_title", "")
	entry.artist = dict.get("artist", "")
	entry.genre = dict.get("genre", "")
	entry.bpm = dict.get("bpm", 0.0)
	entry.instruments = dict.get("instruments", [])
	entry.available_difficulties = []

	entry.note_counts = {}
	entry.note_densities = {}
	entry.difficulty_ratings = {}

	entry.files_valid = dict.get("files_valid", false)
	entry.error_message = dict.get("error_message", "")

	var ad = dict.get("available_difficulties", [])
	for diff in ad:
		entry.available_difficulties.append(int(diff))

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

func _difficulty_info_from_json(dict: Dictionary) -> DetailedDifficultyInfo:
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

# To be obsoleted by the database.
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

# To be obsoleted by the database.
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

# To be obsoleted by the database.
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

	return OK

# Keeping this because the JSON is stored in the difficulties table.
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

func scan_for_songs(rescan := false):
	var dir = DirAccess.open(SONG_DIRECTORY_PATH)
	if not dir:
		push_error("Failed to open song directory.")
		return

	dir.list_dir_begin()
	var folder_name = dir.get_next()
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			print("Found song folder: %s" % folder_name)
			process_song(folder_name, rescan)
		folder_name = dir.get_next()
	dir.list_dir_end()

func process_song(folder_name: String, force_rescan := false):
	const SONGS_TABLE = "songs"
	const DIFFICULTIES_TABLE = "difficulties"
	const SONG_INSERT_VIEW = "v_song_upsert"
	var db = SessionManager.library_db

	# Handle song metadata first
	var song_data = null
	var file_path = "res://song/%s/%s.tres" % [folder_name, folder_name]
	var resource_hash = null
	var file_exists = FileAccess.file_exists(file_path)
	if file_exists:
		resource_hash = FileAccess.get_md5(file_path)
	var condition_string = "folder_id = '%s'" % folder_name
	var select_array: Array = db.select_rows(SONGS_TABLE, condition_string, ["resource_hash", "midi_hash"])
	var result_is_empty := select_array.size() == 0
	if force_rescan or result_is_empty or select_array[0]["resource_hash"] != resource_hash:
		print("Processing song: %s" % folder_name)
		var upsert_dict = {
			"folder_id": folder_name,
			"resource_hash": resource_hash,
		}
		if file_exists:
			song_data = ResourceLoader.load(file_path) as SongData
			upsert_dict.merge(_extract_songdata_meta(song_data))
			db.insert_row(SONG_INSERT_VIEW, upsert_dict) # if the row exists, this will update it
		else:
			upsert_dict["files_ok"] = 0
			upsert_dict["midi_hash"] = null
			db.insert_row(SONGS_TABLE, upsert_dict)
	
	if song_data:
		var midi_hash = null
		if song_data.midi_file:
			midi_hash = FileAccess.get_md5(ResourceUID.ensure_path(song_data.midi_file))
			if result_is_empty or midi_hash != select_array[0]["midi_hash"]:
				var difficulty_rows = []
				var midi_track_indices = song_data.song_track_locations.values()
				for i in DIFFICULTY_LEVELS:
					var track_map: Array[Dictionary] = []
					var total_note_count := 0
					for track_idx in midi_track_indices:
						var note_map = song_data.get_note_map_from_track(track_idx, i)
						total_note_count += note_map.size()
						track_map.append(note_map)
					if total_note_count > 0:
						print("Processing difficulty: %s" % i)
						var ddi: DetailedDifficultyInfo = _calculate_detailed_difficulty(track_map, song_data)
						var row = {
							"song_folder": folder_name,
							"difficulty_offset": i,
							"difficulty_rating": ddi.avg_raw_difficulty,
							"details_json": JSON.stringify(_difficulty_info_to_json(ddi))
						}
						difficulty_rows.append(row)
				if not difficulty_rows.is_empty():
					db.insert_rows(DIFFICULTIES_TABLE, difficulty_rows)


## Creates a dictionary of song metadata for INSERT or UPDATE statements.
## Does not create difficulty entries.
func _extract_songdata_meta(song_data: SongData) -> Dictionary:
	var files_ok := false
	var result := {
		"title": song_data.title,
		"sub_title": song_data.sub_title,
		"artist": song_data.artist,
		"genre": song_data.genre,
		"bpm": song_data.bpm,
		"desc": song_data.description,
		"source_name": song_data.source,
		}
	var midi_path = ResourceUID.ensure_path(song_data.midi_file)
	if not FileAccess.file_exists(midi_path):
		result["files_ok"] = 0
		result["midi_hash"] = null
		return result
	result["midi_hash"] = FileAccess.get_md5(midi_path)
	if song_data.tracks.size() == 0:
		result["files_ok"] = 0
		return result
	files_ok = FileAccess.file_exists(ResourceUID.ensure_path(song_data.click_track))
	var track_count := song_data.tracks.size()
	var inst_layout := ""
	for i in track_count:
		var track = song_data.tracks[i]
		inst_layout += INSTRUMENT_NAMES[track.instrument][0]
		files_ok = files_ok and FileAccess.file_exists(ResourceUID.ensure_path(track.audio_file))
	result["inst_layout"] = inst_layout
	result["files_ok"] = files_ok
	return result

func _process_song_data_to_entry(folder_name: String, song_data: SongData = null) -> SongEntry:
	print("Processing song: %s" % folder_name)
	var result = SongEntry.new()

	result.folder = folder_name
	result.file_path = "res://song/%s/%s.tres" % [folder_name, folder_name]
	if not song_data:
		song_data = ResourceLoader.load(result.file_path) as SongData
	if not song_data:
		print("Failed to load SongData resource at: %s" % result.file_path)
		return result
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

	# TODO: How am I going to store this data?
	var detailed_diffs_info: Dictionary[int, DetailedDifficultyInfo] = {}
	for diff in difficulty_maps.keys():
		var ddi := _calculate_detailed_difficulty(difficulty_maps[diff], song_data)
		result.difficulty_ratings[diff] = ddi.avg_raw_difficulty
		detailed_diffs_info[diff] = ddi

	
	result.detailed_difficulty_info = detailed_diffs_info
	result.files_valid = true
	print("Finished processing song: %s" % folder_name)
	return result


func _process_song_data_in_queue(entry_idx: int):
	var result := SongEntry.new()
	var loaded = _loaded_data[entry_idx]
	var folder_name: String = loaded[0]
	var song_data: SongData = loaded[1]
	result = _process_song_data_to_entry(folder_name, song_data)
	additions[entry_idx] = result

func _calculate_detailed_difficulty(track_maps: Array, song_data: SongData) -> DetailedDifficultyInfo:
	var ddi := DetailedDifficultyInfo.new()
	var track_count = track_maps.size()
	ddi.track_note_counts.resize(track_count)
	ddi.measure_note_counts.resize(track_count)
	ddi.phrase_raw_difficulties.resize(track_count)
	ddi.track_avg_raw_difficulties.resize(track_count)
	for i in range(track_count):
		var note_map = track_maps[i]
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
	return ddi

func _calculate_phrase_difficulty(
	note_map: Dictionary, # Kept for looking up lanes
	sorted_beats: Array, # NEW: The sorted time keys
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
			return 1.0 # Neutral weight for single lane changes
		2:
			return PATTERN_WEIGHT_JUMP
		_:
			return 1.0 # Fallback neutral weight