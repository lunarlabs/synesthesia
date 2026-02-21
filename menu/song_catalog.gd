extends Node

var _song_catalog: Array = []
var _difficulty_catalog: Array = []
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
	midi_hash,
	cover_art,
	cover_art_width,
	cover_art_height,
	cover_art_fmt
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
	midi_hash,
	cover_art,
	cover_art_width,
	cover_art_height,
	cover_art_fmt
FROM v_full_library"""

const FILTER_FOLDER = """WHERE folder_id = ?"""
const FILTER_DIFFICULTY = """WHERE difficulty_offset = ?"""
const FILTER_FOLDER_DIFFICULTY = """WHERE folder_id = ? AND difficulty_offset = ?"""
const FILTER_SOURCE = """WHERE source_name = ?"""

const DEFAULT_ORDER_BY = "ORDER BY sort_key ASC"
const BPM_ORDER_BY = "ORDER BY bpm ASC"
const DIFF_RATING_ORDER_BY = "ORDER BY difficulty_rating DESC"
#endregion

var is_initialized: bool:
	get:
		return _song_catalog.size() > 0
var song_catalog:
	get:
		return _song_catalog
var difficulty_catalog:
	get:
		return _difficulty_catalog

# For each difficulty in each song, detailed info. Array index is instrument track index.
class DetailedDifficultyInfo:
	var track_note_counts: PackedInt32Array
	var measure_note_counts: Array[PackedInt32Array]
	var phrase_raw_difficulties: Array[PackedFloat32Array]
	var track_avg_raw_difficulties: PackedFloat32Array
	var avg_raw_difficulty: float

#region Ingest
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
	if not SessionManager.library_db.query("%s %s;" % [BASE_QUERY, DEFAULT_ORDER_BY]):
		printerr(SessionManager.library_db.error_message)
	_song_catalog = SessionManager.library_db.query_result

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
	if song_data.cover_art:
		var cover_art_img = song_data.cover_art.get_image()
		result["cover_art"] = cover_art_img.get_data()
		result["cover_art_width"] = cover_art_img.get_width()
		result["cover_art_height"] = cover_art_img.get_height()
		result["cover_art_fmt"] = cover_art_img.get_format()
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
#endregion
# TODO: function to get song details from database
# as well as sorting and filtering

#region Difficulty Info Helpers
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
#endregion

func get_resource_path(folder_id: String) -> String:
	return "res://song/%s/%s.tres" % [folder_id, folder_id]

func get_difficulty_rating(folder_id: String, difficulty_offset: int) -> float:
	var db = SessionManager.library_db
	var success = db.query_with_bindings("%s %s;" % [DIFFICULTY_QUERY, FILTER_FOLDER_DIFFICULTY], [folder_id, difficulty_offset])
	var result = db.query_result
	var result_is_empty = result.size() == 0
	if result_is_empty or not success:
		return 0.0
	return result[0]["difficulty_rating"]

#region Sorting, Filtering, and Queries

# TODO: func to make menu structure for carousel menu

#endregion
