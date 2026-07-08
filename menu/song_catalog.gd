extends Node

var _song_catalog: Array = []
var song_indices: Dictionary[String, int] = {}
var _difficulty_catalog: Array = []
var _menu_structure: Array = []
var additions: Array = []

static var CATALOG_JSON_PATH = "user://song_catalog.json"
static var DIFFICULTY_DETAILS_JSON_PATH = "user://song_difficulty_details.json"
static var SONG_DIRECTORY_PATH = "user://song/"
static var SONG_DIRECTORY_PATH_RES = "res://song/"
static var DIFFICULTY_LEVELS = [96, 102, 108, 114] # MIDI note offsets for Easy, Medium, Hard, Expert
static var DIFFICULTY_NAMES = {
	96: "Beginner",
	102: "Basic",
	108: "Advanced",
	114: "Expert",
}
static var INSTRUMENT_NAMES = [
	"drums",
	"bass",
	"guitar",
	"synth",
	"vocals",
	"fx",
]
static var EPSILON = 0.001 # because floating point
static var QUANT_FACTOR_QUARTER = 1.0
static var QUANT_FACTOR_EIGHTH = 1.1
static var QUANT_FACTOR_SIXTEENTH = 1.3
static var QUANT_FACTOR_THIRTY_SECOND = 1.5
static var BASE_SPEED_WEIGHT = 1.0
static var JACK_SPEED_THRESHOLD = 0.2 # seconds between notes to consider "jacking"
static var PATTERN_WEIGHT_JACK = 2.5 # Penalty for fast repeated notes
static var PATTERN_WEIGHT_JUMP = 1.5 # Penalty for Lane 0 -> Lane 2
static var PATTERN_WEIGHT_EASY = 0.8 # Bonus for slow repeated notes

var catalog_loading_scene: PackedScene = preload("res://menu/CatalogLoading.tscn")

#region Query Constants
static var QUERY_BASE = """SELECT
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
	preview_filename,
	cover_art,
	cover_art_width,
	cover_art_height,
	cover_art_fmt
FROM v_song_select"""

static var QUERY_DIFFICULTY = """SELECT
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
	preview_filename,
	cover_art,
	cover_art_width,
	cover_art_height,
	cover_art_fmt
FROM v_full_library"""

static var QUERY_COVER_ART = """SELECT cover_art, cover_art_width, cover_art_height, cover_art_fmt FROM songs WHERE folder_id = ?"""
static var QUERY_PREVIEW_FILE = """SELECT preview_filename FROM songs"""

static var FILTER_FOLDER = """folder_id = ?"""
static var FILTER_DIFFICULTY = """difficulty_offset = ?"""
static var FILTER_FOLDER_DIFFICULTY = """folder_id = ? AND difficulty_offset = ?"""
static var FILTER_BETWEEN_BPM = """bpm BETWEEN ? AND ?"""
static var FILTER_BETWEEN_RATING = """difficulty_rating >= ? AND difficulty_rating < ?"""
static var FILTER_SOURCE = """source_name = ?"""
static var FILTER_GENRE = """genre = ?"""
static var FILTER_CHECKPOINTS = """checkpoint_modifier = ?"""
static var FILTER_RESET = """track_reset = ?"""

static var ORDER_DEFAULT = "ORDER BY sort_key ASC"
static var ORDER_BPM = "ORDER BY bpm ASC"
static var ORDER_DIFF_RATING = "ORDER BY difficulty_rating ASC"

#const MENU_ITEM_TYPES = ["submenu", "category", "song_single_difficulty", "song_all_difficulties"]
static var BPM_BUCKET_SIZE = 20
#endregion

var is_initialized: bool:
	get:
		return not _song_catalog.is_empty()
var song_catalog:
	get:
		return _song_catalog
var difficulty_catalog:
	get:
		return _difficulty_catalog
var menu_structure:
	get:
		if _menu_structure.is_empty():
			make_menu_structure()
		return _menu_structure

# For each difficulty in each song, detailed info. Array index is instrument track index.
class DetailedDifficultyInfo:
	var track_note_counts: PackedInt32Array
	var measure_note_counts: Array[PackedInt32Array]
	var phrase_raw_difficulties: Array[PackedFloat32Array]
	var track_avg_raw_difficulties: PackedFloat32Array
	var avg_raw_difficulty: float

func scan_for_songs(rescan := false):
	var dirs_to_scan = [SONG_DIRECTORY_PATH]
	if OS.has_feature("res_song_catalog"):
		dirs_to_scan.append(SONG_DIRECTORY_PATH_RES)
	for dir_path in dirs_to_scan:
		print("Scanning song directory: %s" % dir_path)
		var dir = DirAccess.open(dir_path)
		if not dir:
			push_error("Failed to open song directory.")
			continue
		var catalog_loading = catalog_loading_scene.instantiate()
		add_child(catalog_loading)
		var loading_label: Label = catalog_loading.get_node("%Label")
		var loading_bar: ProgressBar = catalog_loading.get_node("%ProgressBar")

		# ── Phase 1: Scan folders and check hashes ──
		loading_label.text = "Scanning song folders…"
		loading_bar.indeterminate = true

		var db = SessionManager.library_db

		var existing_hashes: Dictionary = {} # folder_id -> { resource_hash, midi_hash }
		if db.query("SELECT folder_id, resource_hash, midi_hash FROM songs"):
			for row in db.query_result:
				existing_hashes[row["folder_id"]] = row

		var total_folders := 0
		var work_list: Array = []
		dir.list_dir_begin()
		var folder_name = dir.get_next()
		while folder_name != "":
			if dir.current_is_dir() and not folder_name.begins_with("."):
				total_folders += 1
				var file_path = "res://song/%s/%s.tres" % [folder_name, folder_name]
				var file_exists = FileAccess.file_exists(file_path)
				var resource_hash = null
				if file_exists:
					# Check to see if all audio track files exist
					# and clear the file path if not.
					# This will change the resource hash, forcing a rescan.
					var song_data = ResourceLoader.load(file_path) as SongData
					var file_changed := false
					if not FileAccess.file_exists(ResourceUID.ensure_path(song_data.click_track)):
						song_data.click_track = ""
						file_changed = true
					if not FileAccess.file_exists(ResourceUID.ensure_path(song_data.preview_audio)):
						song_data.preview_audio = ""
						file_changed = true
					if not FileAccess.file_exists(ResourceUID.ensure_path(song_data.selection_audio)):
						song_data.selection_audio = "res://assets/transition.mp3"
						file_changed = true
					for i in song_data.tracks.size():
						var track = song_data.tracks[i] as SongTrackData
						if not FileAccess.file_exists(ResourceUID.ensure_path(track.audio_file)):
							print("Track %s: Audio file not found!" % track.midi_track_name)
							track.audio_file = ""
							file_changed = true
					if file_changed:
						ResourceSaver.save(song_data)

					resource_hash = FileAccess.get_md5(file_path)
				var prev = existing_hashes.get(folder_name, {})
				var is_new = prev.is_empty()
				var hash_changed = rescan or is_new or prev.get("resource_hash") != resource_hash
				if hash_changed:
					work_list.append({
						"folder": folder_name,
						"file_exists": file_exists,
						"resource_hash": resource_hash,
						"is_new": is_new,
						"prev_midi_hash": prev.get("midi_hash"),
					})
			folder_name = dir.get_next()
		dir.list_dir_end()

		print("Scan complete: %d folders found, %d need processing." % [total_folders, work_list.size()])

		# ── Phase 2: Process only changed songs ──
		if work_list.is_empty():
			loading_label.text = "Library is up to date."
		else:
			loading_bar.indeterminate = false
			loading_bar.min_value = 0
			loading_bar.max_value = work_list.size()
			loading_bar.value = 0
			for i in work_list.size():
				var item = work_list[i]
				loading_label.text = "Processing song %d / %d: %s" % [i + 1, work_list.size(), item.folder]
				loading_bar.value = i
				await get_tree().process_frame
				process_song(item)
			loading_bar.value = work_list.size()

		# Refresh catalog
		if not db.query("%s %s;" % [QUERY_BASE, ORDER_DEFAULT]):
			printerr(db.error_message)
		_song_catalog = db.query_result
		for i in range(_song_catalog.size()):
			song_indices[_song_catalog[i]["folder_id"]] = i

		catalog_loading.queue_free()

#region Ingest
## Processes a single song folder that was flagged as changed during the scan phase.
## scan_info is a Dictionary with keys: folder, file_exists, resource_hash, is_new, prev_midi_hash.
func process_song(scan_info: Dictionary):
	var songs_table = "songs"
	var difficulties_table = "difficulties"
	var song_insert_view = "v_song_upsert"
	var db = SessionManager.library_db

	var folder_name: String = scan_info.folder
	var file_exists: bool = scan_info.file_exists
	var resource_hash = scan_info.resource_hash
	var is_new: bool = scan_info.is_new
	var prev_midi_hash = scan_info.prev_midi_hash

	print("Processing song: %s" % folder_name)

	# Handle song metadata
	var song_data: SongData = null
	var upsert_dict = {
		"folder_id": folder_name,
		"resource_hash": resource_hash,
	}

	if file_exists:
		var file_path = "res://song/%s/%s.tres" % [folder_name, folder_name]
		song_data = ResourceLoader.load(file_path) as SongData
		upsert_dict.merge(_extract_songdata_meta(song_data))
		db.insert_row(song_insert_view, upsert_dict) # if the row exists, this will update it
	else:
		upsert_dict["files_ok"] = 0
		upsert_dict["midi_hash"] = null
		db.insert_row(songs_table, upsert_dict)

	# Handle difficulty calculation if MIDI changed
	if song_data and song_data.midi_file:
		var midi_hash = FileAccess.get_md5(ResourceUID.ensure_path(song_data.midi_file))
		if is_new or midi_hash != prev_midi_hash:
			var difficulty_rows = []
			var difficulty_track_maps: Array[Array] = [] # parallel array for dedup
			var midi_track_indices = song_data.song_track_locations.values()
			for i in DIFFICULTY_LEVELS:
				var track_map: Array[Dictionary] = []
				var total_note_count := 0
				for track_idx in midi_track_indices:
					var note_map = song_data.get_note_map_from_track(track_idx, i)
					total_note_count += note_map.size()
					track_map.append(note_map)
				if total_note_count > 0:
					print("  Processing difficulty: %s" % i)
					var ddi: DetailedDifficultyInfo = _calculate_detailed_difficulty(track_map, song_data)
					var row = {
						"song_folder": folder_name,
						"difficulty_offset": i,
						"difficulty_rating": ddi.avg_raw_difficulty,
						"details_json": JSON.stringify(_difficulty_info_to_json(ddi))
					}
					difficulty_rows.append(row)
					difficulty_track_maps.append(track_map)
			# Deduplicate: when multiple tiers share identical note maps
			# (same timings + lane patterns), keep only the highest offset.
			var unique_rows: Array = []
			var unique_maps: Array[Array] = []
			for idx in range(difficulty_rows.size() - 1, -1, -1):
				var is_duplicate := false
				for kept_map in unique_maps:
					if _track_maps_equal(difficulty_track_maps[idx], kept_map):
						print("  Skipping duplicate difficulty %s (identical chart)" % difficulty_rows[idx]["difficulty_offset"])
						is_duplicate = true
						break
				if not is_duplicate:
					unique_rows.append(difficulty_rows[idx])
					unique_maps.append(difficulty_track_maps[idx])
			if not unique_rows.is_empty():
				db.insert_rows(difficulties_table, unique_rows)


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
		"preview_filename": song_data.preview_audio.get_file(),
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
#endregion

#region Difficulty Calculation
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
	var active_measures := 0
	for m in range(song_data.total_measures):
		var active_tracks := 0
		var measure_sum := 0.0
		for i in range(track_count):
			var v = ddi.phrase_raw_difficulties[i][m]
			if v > 0.0:
				active_tracks += 1
				measure_sum += v
		if active_tracks > 0:
			total_avg += measure_sum / float(active_tracks)
			active_measures += 1
	ddi.avg_raw_difficulty = total_avg / float(max(active_measures, 1))
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

## Returns true when two arrays of note-map dictionaries are identical.
## Used to detect difficulty tiers that share the exact same chart data.
func _track_maps_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i] != b[i]:
			return false
	return true
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
	var success = db.query_with_bindings("%s WHERE %s;" % [QUERY_DIFFICULTY, FILTER_FOLDER_DIFFICULTY], [folder_id, difficulty_offset])
	var result = db.query_result
	var result_is_empty = result.size() == 0
	if result_is_empty or not success:
		return 0.0
	return result[0]["difficulty_rating"]

#region Sorting, Filtering, and Queries

func get_folder_ids() -> Array:
	var db = SessionManager.library_db
	var success = db.query("%s %s;" % [QUERY_BASE, ORDER_DEFAULT])
	var result = db.query_result
	var result_is_empty = result.size() == 0
	if result_is_empty or not success:
		return []
	var folder_ids = []
	for i in range(result.size()):
		folder_ids.append(result[i]["folder_id"])
	return folder_ids

func get_song_info(folder_id: String) -> Dictionary:
	var db = SessionManager.library_db
	var success = db.query_with_bindings("%s WHERE %s;" % [QUERY_BASE, FILTER_FOLDER], [folder_id])
	var result = db.query_result
	var result_is_empty = result.size() == 0
	if result_is_empty or not success:
		return {}
	return result[0]

func get_song_preview(folder_id: String) -> AudioStream:
	var db = SessionManager.library_db
	var success = db.query_with_bindings("%s WHERE %s;" % [QUERY_PREVIEW_FILE, FILTER_FOLDER], [folder_id])
	var result = db.query_result
	var result_is_empty = result.size() == 0
	if result_is_empty or not success:
		return null
	var preview_filename = result[0]["preview_filename"]
	if preview_filename == null:
		return null
	var resource = load("res://song/%s/%s" % [folder_id, preview_filename])
	return resource

func get_difficulties(folder_id: String) -> Array:
	var db = SessionManager.library_db
	var success = db.query_with_bindings("%s WHERE %s;" % [QUERY_DIFFICULTY, FILTER_FOLDER], [folder_id])
	var result = db.query_result
	var result_is_empty = result.size() == 0
	if result_is_empty or not success:
		return []
	return result

func get_cover_art(folder_id: String) -> ImageTexture:
	var db = SessionManager.library_db
	var success = db.query_with_bindings("%s WHERE %s;" % [QUERY_COVER_ART, FILTER_FOLDER], [folder_id])
	var result = db.query_result
	var result_is_empty = result.size() == 0
	if result_is_empty or not success:
		return null
	var cover_art = result[0]["cover_art"]
	if cover_art == null:
		return null
	var cover_art_width = result[0]["cover_art_width"]
	var cover_art_height = result[0]["cover_art_height"]
	var cover_art_fmt = result[0]["cover_art_fmt"]
	var image = Image.create_from_data(cover_art_width, cover_art_height, false, cover_art_fmt, cover_art)
	var image_texture = ImageTexture.create_from_image(image)
	return image_texture

#endregion

#region Menu Structure
# TODO: func to make menu structure for carousel menu
func make_menu_structure():
	_menu_structure.clear()
	var db = SessionManager.library_db
	# Pre-fetch all difficulty ratings into a local cache to avoid
	# one SQL query per song per difficulty tier during menu construction.
	var diff_cache: Dictionary = {}
	if db.query("SELECT song_folder, difficulty_offset, difficulty_rating FROM difficulties"):
		for row in db.query_result:
			var fid: String = row["song_folder"]
			if not diff_cache.has(fid):
				diff_cache[fid] = {}
			diff_cache[fid][row["difficulty_offset"]] = row["difficulty_rating"]
	# first determine bucket ranges
	var success = db.query("SELECT MIN(bpm), MAX(bpm) FROM songs")
	var result = db.query_result
	var result_is_empty = result.size() == 0
	var min_bpm = result[0]["MIN(bpm)"] if not result_is_empty else null
	var max_bpm = result[0]["MAX(bpm)"] if not result_is_empty else null
	if result_is_empty or not success or min_bpm == null or max_bpm == null:
		return
	var min_bucket = int(floor(min_bpm / float(BPM_BUCKET_SIZE)))
	var max_bucket = int(ceil(max_bpm / float(BPM_BUCKET_SIZE)))
	var num_buckets = max_bucket - min_bucket
	var buckets = []
	for i in range(num_buckets):
		var bucket_min = (min_bucket + i) * BPM_BUCKET_SIZE
		var bucket_max = bucket_min + BPM_BUCKET_SIZE
		buckets.append({
			"min": bucket_min,
			"max": bucket_max
		})
	
	success = db.query("SELECT MAX(difficulty_rating) FROM difficulties")
	result = db.query_result
	result_is_empty = result.size() == 0
	var max_difficulty_rating = result[0]["MAX(difficulty_rating)"] if not result_is_empty else null
	if result_is_empty or not success or max_difficulty_rating == null:
		return
	var difficulty_ceil = int(ceil(max_difficulty_rating))

	success = db.query("SELECT * FROM sources ORDER BY name ASC")
	result = db.query_result
	result_is_empty = result.size() == 0
	if result_is_empty or not success:
		return
	var sources = result
	
	var title_menu_entry = {
		&"name": "All Songs",
		&"type": &"submenu",
		&"children": []
	}

	success = db.query("%s WHERE files_ok = 1 %s;" % [QUERY_BASE, ORDER_DEFAULT])
	result = db.query_result
	result_is_empty = result.size() == 0
	if not result_is_empty and success:
		for i in result.size():
			var info = result[i]
			var entry = {
				&"name": info.title,
				&"sub_title": info.sub_title,
				&"folder_id": info.folder_id,
				&"type": &"song_all_difficulties",
				&"difficulties": {}
			}
			for difficulty_offset in DIFFICULTY_LEVELS:
				var rating: float = diff_cache.get(info.folder_id, {}).get(difficulty_offset, 0.0)
				if rating > 0.0:
					entry[&"difficulties"][difficulty_offset] = rating

			if not entry.difficulties.is_empty():
				title_menu_entry.children.append(entry)
	_menu_structure.append(title_menu_entry)

	var source_menu_entry = {
		&"name": "Sources",
		&"type": &"submenu",
		&"children": []
	}

	for i in sources.size():
		var source = sources[i]
		var entry = {
			&"name": source.name,
			&"type": &"category",
			&"open": false,
			&"children": []
		}
		success = db.query_with_bindings("%s WHERE %s %s;" % [QUERY_BASE, FILTER_SOURCE, ORDER_DEFAULT], [source.name])
		result = db.query_result
		result_is_empty = result.size() == 0
		if result_is_empty or not success:
			push_warning("Failed to query songs for source: %s" % source.name)
			continue
		for j in result.size():
			var info = result[j]
			var song_entry = {
				&"name": info.title,
				&"sub_title": info.sub_title,
				&"folder_id": info.folder_id,
				&"type": &"song_all_difficulties",
				&"difficulties": {}
			}
			for difficulty_offset in DIFFICULTY_LEVELS:
				var rating: float = diff_cache.get(info.folder_id, {}).get(difficulty_offset, 0.0)
				if rating > 0.0:
					song_entry[&"difficulties"][difficulty_offset] = rating
			if not song_entry.difficulties.is_empty():
				entry.children.append(song_entry)
		source_menu_entry.children.append(entry)
	_menu_structure.append(source_menu_entry)

	var genre_menu_entry = {
		&"name": "Genre",
		&"type": &"submenu",
		&"children": []
	}

	success = db.query("SELECT DISTINCT genre FROM songs ORDER BY genre ASC")
	result = db.query_result
	result_is_empty = result.size() == 0
	if not result_is_empty and success:
		for i in result.size():
			var genre_name = result[i]["genre"]
			var entry = {
				&"name": genre_name,
				&"type": &"category",
				&"open": false,
				&"children": []
			}
			success = db.query_with_bindings("%s WHERE %s %s;" % [QUERY_BASE, FILTER_GENRE, ORDER_DEFAULT], [genre_name])
			var genre_results = db.query_result
			if not genre_results.is_empty() and success:
				for j in genre_results.size():
					var info = genre_results[j]
					var song_entry = {
						&"name": info.title,
						&"sub_title": info.sub_title,
						&"folder_id": info.folder_id,
						&"type": &"song_all_difficulties",
						&"difficulties": {}
					}
					for difficulty_offset in DIFFICULTY_LEVELS:
						var rating: float = diff_cache.get(info.folder_id, {}).get(difficulty_offset, 0.0)
						if rating > 0.0:
							song_entry[&"difficulties"][difficulty_offset] = rating
					if not song_entry.difficulties.is_empty():
						entry.children.append(song_entry)
			if not entry.children.is_empty():
				genre_menu_entry.children.append(entry)
	_menu_structure.append(genre_menu_entry)

	var bpm_menu_entry = {
		&"name": "BPM",
		&"type": &"submenu",
		&"children": []
	}

	for i in buckets.size():
		var bucket = buckets[i]
		var entry = {
			&"name": "%d-%d bpm" % [bucket.min, bucket.max],
			&"type": &"category",
			&"open": false,
			&"children": []
		}
		success = db.query_with_bindings("%s WHERE %s %s;" % [QUERY_BASE, FILTER_BETWEEN_BPM, ORDER_BPM], [bucket.min, bucket.max])
		result = db.query_result
		result_is_empty = result.size() == 0
		if result_is_empty or not success:
			push_warning("Failed to query songs for BPM range: %d-%d" % [bucket.min, bucket.max])
			continue
		for j in result.size():
			var info = result[j]
			var song_entry = {
				&"name": info.title,
				&"sub_title": info.sub_title,
				&"folder_id": info.folder_id,
				&"type": &"song_all_difficulties",
				&"difficulties": {}
			}
			for difficulty_offset in DIFFICULTY_LEVELS:
				var rating: float = diff_cache.get(info.folder_id, {}).get(difficulty_offset, 0.0)
				if rating > 0.0:
					song_entry[&"difficulties"][difficulty_offset] = rating
			if not song_entry.difficulties.is_empty():
				entry.children.append(song_entry)
		bpm_menu_entry.children.append(entry)
	_menu_structure.append(bpm_menu_entry)

	var difficulty_menu_entry = {
		&"name": "Difficulty",
		&"type": &"submenu",
		&"children": []
	}

	for i in range(0, difficulty_ceil + 1):
		var entry = {
			&"name": "Level %d" % i,
			&"type": &"category",
			&"open": false,
			&"children": []
		}
		success = db.query_with_bindings("%s WHERE %s %s;" % [QUERY_DIFFICULTY, FILTER_BETWEEN_RATING, ORDER_DIFF_RATING], [i, i + 1])
		result = db.query_result
		result_is_empty = result.size() == 0
		if result_is_empty or not success:
			push_warning("Failed to query songs for difficulty: %d" % i)
			continue
		for j in result.size():
			var info = result[j]
			var song_entry = {
				&"name": info.title,
				&"sub_title": info.sub_title,
				&"difficulty_offset": info.difficulty_offset,
				&"difficulty_rating": info.difficulty_rating,
				&"folder_id": info.folder_id,
				&"type": &"song_single_difficulty",
			}
			entry.children.append(song_entry)
		difficulty_menu_entry.children.append(entry)
	_menu_structure.append(difficulty_menu_entry)


#endregion
