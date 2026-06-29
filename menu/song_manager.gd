extends Node
class_name SynRoadSongManager

@export_file("*.tres") var song_file: String = ""
@export_enum("Beginner:96", "Intermediate:102", "Advanced:108", "Expert:114")
var difficulty: int = 96
@export_group("Modifiers")
@export_enum("Normal", "Constant Drain", "No Recover", "Sudden Death", "No Fail") var energy_modifier: int = 0
@export_enum("Normal", "Disabled", "Barrier 2", "Barrier 3", "Barrier 4") var checkpoint_modifier: int = 0
@export var streak_hints: bool = true
@export_enum("Normal", "Loose", "Strict") var timing_modifier: int = 0
@export_enum("Normal:12", "Fast Reset 1:10", "Fast Reset 2:8", "Dynamic Reset:-1") var fast_track_reset: int = 12
@export var autoblast: bool = false
@export_range(0.5, 3.0, 0.25) var hi_speed: float = 1.0

var constant_velocity_mode = false
var can_pause := false

const SONG_SCENE: PackedScene = preload("res://entities/song.tscn")
const LOAD_SCENE: PackedScene = preload("res://menu/load_screen.tscn")

const DIFFICULTY_NAMES = {
	96: "DIFF_96",
	102: "DIFF_102",
	108: "DIFF_108",
	114: "DIFF_114"
}

enum EnergyModifiers {
	NORMAL,
	DRAIN,
	NO_RECOVER,
	SUDDEN_DEATH,
	NO_FAIL,
}

enum CheckpointModifiers {
	CHECKPOINT,
	NO_CHECKPOINT_RECOVERY,
	BARRIER_2X,
	BARRIER_3X,
	BARRIER_4X,
}

enum TimingModifiers {
	NORMAL,
	LOOSE,
	STRICT,
}

enum TrackReset {
	NORMAL = 12,
	FAST_ONE = 10,
	FAST_TWO = 8,
	DYNAMIC = -1,
}

const ENERGY_MODIFIER_NAMES = [
	"Energy",
	"Drain",
	"No Recover",
	"S.Death",
    "No Fail"
]
const CHECKPOINT_MODIFIER_NAMES = [
	"Checkpoint",
	"No Checkpoint",
	"Barrier 2",
	"Barrier 3",
	"Barrier 4"
]
const TIMING_MODIFIER_NAMES = [
	"Timing",
	"Loose",
    "Strict"
]

const FAST_RESET_NAMES = {
	12: "Track Reset",
	10: "Fast Reset 1",
	8: "Fast Reset 2",
	-1: "Dynamic Reset"
}

const ACCURACY_THRESHOLDS = {
	"AAA": 97.0,
	"AA": 93.0,
	"A": 90.0,
	"B": 80.0,
	"C": 70.0,
	"D": 60.0,
	"E": 50.0,
	"F": 0.00,
}

enum FinishMode {
	COMPLETE,
	FAILED,
	PRACTICE,
	AUTOBLAST,
}

const STANDARD_LENGTH_PER_BEAT = -4.0
const BEATS_PER_MEASURE = 4.0
const CHUNK_LENGTH_IN_MEASURES = 8
const TIMING_WINDOWS = [0.08, 0.1, 0.06, ]
const MISS_WINDOW_OFFSET = 0.01
const STANDARD_BPM = 120.0

@onready var pause_panel: PanelContainer = $PausePanel
@onready var btn_continue: Button = $PausePanel/VBoxContainer/ContinueButton
@onready var btn_restart: Button = $PausePanel/VBoxContainer/RestartButton
@onready var btn_quit: Button = $PausePanel/VBoxContainer/QuitButton
@onready var result_screen: Control = $SongResult

var catalog_entry: Dictionary = {}
# For this refactor, we'll use time instead of beats for everything
# Also measures will be zero-indexed
var song_data: SongData
var song_instance: SynRoadSong
var load_screen: ColorRect
var preprocessor: SynRoadTrackPreprocessor
var waiting_for_task: bool = false
var task = null
var load_result: Dictionary = {}
var song_name: String
var synced_stream: AudioStreamSynchronized
var midi_hash: String
var note_maps: Array[Dictionary]
var track_data: Array[Dictionary]
var _playable_measures_by_track: Array[PackedByteArray] = []
var total_measures: int
var length_multiplier: float
var seconds_per_beat: float
var length_per_beat: float
var ideal_playhead_speed: float
var finish_time: float
## A zero-based array of measure start times (in seconds.)
var measure_times: PackedFloat32Array = []
## the Z-position of measures on the track
var measure_positions: PackedFloat32Array = []
var measure_in_chunks: PackedInt32Array = []
var chunk_count := 0
var checkpoint_positions: PackedFloat32Array = []
var checkpoint_measures: PackedInt32Array = []
var suppressed_measure_mask: Array[bool] = []
## For barrier mode: array of {checkpoint, zone_start, streak_start, reset_at} dicts
var barrier_zones: Array[Dictionary] = []
var hit_window: float
var miss_window: float

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	load_screen = LOAD_SCENE.instantiate()
	add_child.call_deferred(load_screen)
	if song_file == "":
		# Were we passed a catalog entry directly?
		if catalog_entry.has("folder_id"):
			var song_info_container = load_screen.get_node("SongInfo")
			var title_label = song_info_container.get_node("TitleLabel") as Label
			var artist_label = song_info_container.get_node("ArtistLabel") as Label
			if catalog_entry.sub_title == null or catalog_entry.sub_title.is_empty():
				title_label.text = catalog_entry["title"]
			else:
				title_label.text = "%s\n%s" % [catalog_entry["title"], catalog_entry["sub_title"]]
			artist_label.text = catalog_entry["artist"]
			song_file = SongCatalog.get_resource_path(catalog_entry.folder_id)
			midi_hash = catalog_entry.midi_hash
			result_screen.populate_from_catalog_entry(catalog_entry, difficulty)
			var tween = create_tween()
			tween.tween_property(song_info_container, "modulate:a", 1.0, 1.0)
			await tween.finished
		else:
			push_error("No song file provided")
			return
	get_window().focus_exited.connect(_on_lose_focus)
	song_name = song_file.get_file().get_slice(".", 0)
	energy_modifier = SessionManager.modifiers.get("energy_modifier", EnergyModifiers.NORMAL)
	fast_track_reset = SessionManager.modifiers.get("fast_track_reset", TrackReset.NORMAL)
	checkpoint_modifier = SessionManager.modifiers.get("checkpoint_mode", CheckpointModifiers.CHECKPOINT)
	timing_modifier = SessionManager.modifiers.get("timing_mode", TimingModifiers.NORMAL)
	streak_hints = SessionManager.modifiers.get("streak_hints", true)
	constant_velocity_mode = SessionManager.modifiers.get("constant_velocity_mode", false)
	hi_speed = SessionManager.modifiers.get("length_multiplier", 1.0)
	autoblast = SessionManager.modifiers.get("autoblast", false)

	var prepare_func = Callable(self , "_prepare_song_data").bind(load_result)
	task = WorkerThreadPool.add_task(prepare_func)
	waiting_for_task = true
	
	hit_window = TIMING_WINDOWS[timing_modifier]
	miss_window = hit_window + MISS_WINDOW_OFFSET
	
	
	# Connect pause menu buttons
	btn_continue.pressed.connect(_on_continue_pressed)
	btn_restart.pressed.connect(_on_restart_pressed)
	btn_quit.pressed.connect(_on_quit_pressed)
	
	# Connect result screen buttons
	var result_exit_btn = result_screen.get_node("%ExitButton") as Button
	var result_restart_btn = result_screen.get_node("%RestartButton") as Button
	result_exit_btn.pressed.connect(_on_quit_pressed)
	result_restart_btn.pressed.connect(_on_restart_pressed)

@warning_ignore("unused_parameter")
func _process(delta: float) -> void:
	if waiting_for_task:
		if WorkerThreadPool.is_task_completed(task):
			var err = WorkerThreadPool.wait_for_task_completion(task)
			if err != OK:
				push_error("Failed to wait for task completion")
				return
			if not load_result.get("success", false):
				return
			print("handing over to song node now")
			if OS.has_feature("editor"):
				var json_out = _format_json(load_result)
				var proc_file_path = "user://preprocessor_result.json"
				var file = FileAccess.open(proc_file_path, FileAccess.WRITE)
				if file:
					file.store_string(json_out)
					file.close()
			song_instance = SONG_SCENE.instantiate() as SynRoadSong
			song_instance.song_failed.connect(_on_song_failed)
			song_instance.song_finished.connect(_on_song_finished)
			add_child.call_deferred(song_instance)
			load_screen.color = Color(1, 1, 1, 0)
			waiting_for_task = false
			await song_instance.song_prepared
			song_instance.start_song()
			if not get_window().has_focus():
				_toggle_pause()

func _prepare_song_data(out_load_result: Dictionary) -> void:
	song_data = load(song_file) as SongData
	if not song_data:
		push_error("Failed to load song data from %s" % song_file)
		out_load_result["success"] = false
		return
	if OS.has_feature("editor"):
		out_load_result["song_file"] = song_file
		out_load_result["song_name"] = song_name
		var metadata: Dictionary = {
			"artist": song_data.artist,
			"title": song_data.title,
			"sub_title": song_data.sub_title,
			"bpm": song_data.bpm,
			"lead_in_measures": song_data.lead_in_measures,
			"playable_measures": song_data.playable_measures,
		}
		out_load_result["metadata"] = metadata
		out_load_result["difficulty"] = difficulty
	note_maps = _get_note_maps()
	if note_maps.size() == 0:
		push_error("No note maps found for song %s" % song_file)
		out_load_result["success"] = false
		return
	for i in note_maps.size():
		var playable_measures = PackedByteArray()
		playable_measures.resize(song_data.lead_in_measures + song_data.playable_measures)
		for note in note_maps[i].keys():
			var measure = int(note / (BEATS_PER_MEASURE))
			if measure >= 0 and measure < playable_measures.size():
				playable_measures[measure] = 1
		_playable_measures_by_track.append(playable_measures)
	seconds_per_beat = song_data.seconds_per_beat
	if constant_velocity_mode:
		length_multiplier = (hi_speed * STANDARD_BPM) / song_data.bpm
		print("length_multiplier set to %.3f (constant velocity: %.2fx, song tempo %.2f bpm)" % [length_multiplier, hi_speed, song_data.bpm])
	else:
		length_multiplier = hi_speed / song_data.scale_fudge_factor
		print("Length multiplier set to %.3f (Hi-Speed: %.2f, Fudge: %.2f)" % [length_multiplier, hi_speed, song_data.scale_fudge_factor])
	length_per_beat = STANDARD_LENGTH_PER_BEAT * length_multiplier
	ideal_playhead_speed = length_per_beat / seconds_per_beat
	print("Ideal playhead speed: %.3f units/sec" % ideal_playhead_speed)

	total_measures = song_data.lead_in_measures + song_data.playable_measures
	finish_time = total_measures * seconds_per_beat * BEATS_PER_MEASURE
	for i in range(total_measures + 2):
		#print("calculate chunk %d" % i)
		measure_times.append(seconds_per_beat * BEATS_PER_MEASURE * i)
		measure_positions.append(i * length_per_beat * BEATS_PER_MEASURE)
		@warning_ignore("integer_division")
		var chunk = i / CHUNK_LENGTH_IN_MEASURES
		measure_in_chunks.append(chunk)
		chunk_count = max(chunk_count, chunk + 1)
	chunk_count += 1

	var suppressed_measures: Array[int] = []
	suppressed_measure_mask.resize(total_measures)
	print("suppressing lead-in measures")
	for measure in range(song_data.lead_in_measures):
		# There may be notes in the lead in measures. There *shouldn't*,
		# but sometimes there are. Suppress the measures so that playable notes 
		# don't appear before the song start.
		suppressed_measure_mask[measure] = true
		if OS.has_feature("editor"):
			suppressed_measures.append(measure)
	print("suppressing checkpoint measures")
	for measure in song_data.checkpoints:
		var actual_measure = measure + song_data.lead_in_measures
		checkpoint_measures.append(actual_measure)
		checkpoint_positions.append(measure_positions[actual_measure])
		match checkpoint_modifier:
			0:
				suppressed_measure_mask[actual_measure] = true
				suppressed_measure_mask[actual_measure + 1] = true
				if OS.has_feature("editor"):
					suppressed_measures.append(actual_measure)
					suppressed_measures.append(actual_measure + 1)
				# Standard checkpoint: suppress checkpoint measure and the following measure for recovery buffer
			1:
				# Disabled -- leave the checkpoint gates as is but they won't do anything
				pass
			2, 3, 4:
				# Barrier mode: set up 10-measure approach zone
				# Zone start clamped to last checkpoint measure (or lead-in boundary)
				var last_cp = checkpoint_measures[-2] if checkpoint_measures.size() > 1 else song_data.lead_in_measures
				var zone_start = max(last_cp, actual_measure - 10)
				# Suppress first 2 measures of zone (approach buffer)
				if zone_start >= 0 and zone_start < total_measures:
					suppressed_measure_mask[zone_start] = true
					if OS.has_feature("editor"):
						suppressed_measures.append(zone_start)
				if zone_start + 1 >= 0 and zone_start + 1 < total_measures:
					suppressed_measure_mask[zone_start + 1] = true
					if OS.has_feature("editor"):
						suppressed_measures.append(zone_start + 1)
				# Suppress C and C+1 (post-checkpoint)
				suppressed_measure_mask[actual_measure] = true
				if actual_measure + 1 < total_measures:
					suppressed_measure_mask[actual_measure + 1] = true
					if OS.has_feature("editor"):
						suppressed_measures.append(actual_measure + 1)
				# Record barrier zone for preprocessor
				barrier_zones.append({
					"checkpoint": actual_measure,
					"zone_start": zone_start,
					"streak_start": zone_start + 2,
					"reset_at": min(actual_measure + 2, total_measures),
				})
	if OS.has_feature("editor"):
		out_load_result["suppressed_measures"] = suppressed_measures

	track_data.resize(song_data.tracks.size())
	_fetch_track_data()
	preprocessor.wait_for_all()
	var results = preprocessor.take_completed()
	_apply_preprocessor_results(results)
	if track_data.size() == 0:
		push_error("No valid track data found for selected difficulty %d" % difficulty)
		OS.alert("The selected song does not have valid note data for the chosen difficulty. Please select a different difficulty or song.")
		out_load_result["success"] = false
		return
	# Only load the audio files if everything worked out OK
	synced_stream = song_data.get_audio_stream_synchronized()
	out_load_result["success"] = true


func _fetch_track_data() -> void:
	preprocessor = SynRoadTrackPreprocessor.new()
	print("loading midi data")
	for i in song_data.tracks.size():
		var track_info = song_data.tracks[i] as SongTrackData
		var midi_track_idx = song_data.song_track_locations.get(track_info.midi_track_name, -1)
		if midi_track_idx == -1:
			push_error("Track name %s not found in MIDI data." % track_info.midi_track_name)
			continue
		var job = {
			"song_track_index": i,
			"note_map": note_maps[i],
			"seconds_per_beat": 60.0 / song_data.bpm,
			"chunk_count": chunk_count,
			"suppressed_measure_mask": suppressed_measure_mask,
			"track_reset": fast_track_reset,
			"length_per_beat": length_per_beat,
			"total_measures": total_measures,
			"barrier_zones": barrier_zones,
			"lead_in_measures": song_data.lead_in_measures, # damnyou, bulletproof!
			"playable_measure_grid": _playable_measures_by_track,
		}
		preprocessor.queue_job(job)

func _get_note_maps() -> Array[Dictionary]:
	print("getting note maps...")
	var result: Array[Dictionary] = []
	for i in song_data.tracks.size():
		var track_info = song_data.tracks[i] as SongTrackData
		var midi_track_idx = song_data.song_track_locations.get(track_info.midi_track_name, -1)
		if midi_track_idx == -1:
			push_error("Track name %s not found in MIDI data." % track_info.midi_track_name)
			continue
		result.append(song_data.get_note_map_from_track(midi_track_idx, difficulty))
	return result

func _apply_preprocessor_results(results: Array) -> void:
	print("applying preprocessor results")
	for result in results:
		var track_info = song_data.tracks[result.track_index] as SongTrackData
		if result.result.note_map.size() > 0:
			track_data[result.track_index]["track_data"] = result.result
			track_data[result.track_index]["track_info"] = track_info

func _format_json(loaded_data: Dictionary) -> String:
	var json_ready = {
		"metadata": loaded_data.metadata,
		"seconds_per_beat": seconds_per_beat,
		"suppressed_measures": loaded_data.suppressed_measures,
		"difficulty": difficulty,
		"track_data": [],
	}
	for track in track_data:
		var track_dict: Dictionary = {
			"track_name": track.track_info.midi_track_name,
			"track_instrument": track.track_info.instrument,
			"notes": [],
			"phrases": [],
		}
		for i in track.track_data.note_times.size():
			track_dict["notes"].append([
				track.track_data.note_times[i],
				track.track_data.note_map.keys()[i],
				track.track_data.note_map.values()[i],
			])
		for i in track.track_data.phrase_starts.size():
			track_dict["phrases"].append({
				"start_measure": track.track_data.phrase_starts[i],
				"length_in_measures": track.track_data.phrase_lengths[i],
				"first_note_index": track.track_data.phrase_first_note_indices[i],
				"note_count": track.track_data.phrase_note_counts[i],
				"activation_length": track.track_data.phrase_activation_lengths[i],
				"reset_at": track.track_data.phrase_next_measures[i],
			})
		json_ready.track_data.append(track_dict)
	return JSON.stringify(json_ready, "\t")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_toggle_pause()

func _on_song_failed(stats) -> void:
	var percent_completed = (float(stats.measure) / (song_data.playable_measures + song_data.lead_in_measures)) * 100.0
	var song_stats := SessionManager.SongResult.new()
	song_stats.difficulty = difficulty
	song_stats.energy_modifier = energy_modifier
	song_stats.checkpoint_modifier = checkpoint_modifier
	song_stats.fast_track_reset = fast_track_reset
	song_stats.timing_modifier = timing_modifier
	song_stats.score = stats["score"]
	song_stats.max_streak = stats["max_streak"]
	var accuracy = (float(stats.phrases_completed) / (stats.phrases_completed + stats.phrases_missed)) * percent_completed
	song_stats.accuracy = accuracy
	song_stats.streak_breaks = stats["streak_breaks"]
	song_stats.percent_completed = percent_completed
	song_stats.clear_state = SessionManager.SongResult.ClearState.FAILED
	var finish_state = FinishMode.FAILED

	song_instance.hud.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	result_screen.display(finish_state, song_stats,
		SessionManager.get_song_best_record(midi_hash, difficulty))
	SessionManager.record_song_result(midi_hash, song_stats)
	#SessionManager.save_song_records()

func _on_song_finished(stats) -> void:
	var song_stats := SessionManager.SongResult.new()
	song_stats.difficulty = difficulty
	song_stats.energy_modifier = energy_modifier
	song_stats.checkpoint_modifier = checkpoint_modifier
	song_stats.fast_track_reset = fast_track_reset
	song_stats.timing_modifier = timing_modifier
	song_stats.score = stats["score"]
	song_stats.max_streak = stats["max_streak"]
	var accuracy = (float(stats.phrases_completed) / (stats.phrases_completed + stats.phrases_missed)) * 100.0
	song_stats.accuracy = accuracy
	song_stats.streak_breaks = stats["streak_breaks"]
	song_stats.percent_completed = 100.0
	song_stats.calculate_rank()
	var finish_state = FinishMode.PRACTICE if song_stats.energy_modifier == 4 else FinishMode.COMPLETE
	var valid_record := false
	if autoblast:
		finish_state = FinishMode.AUTOBLAST
		song_stats.clear_state = SessionManager.SongResult.ClearState.AUTOBLASTED
	elif song_stats.energy_modifier == 4:
		song_stats.clear_state = SessionManager.SongResult.ClearState.NOT_PLAYED
	else:
		valid_record = true
		if stats["perfect"]:
			song_stats.clear_state = SessionManager.SongResult.ClearState.PERFECT_RUN
		else:
			match timing_modifier:
				TimingModifiers.LOOSE:
					song_stats.clear_state = SessionManager.SongResult.ClearState.LOOSE_CLEAR
				TimingModifiers.STRICT:
					song_stats.clear_state = SessionManager.SongResult.ClearState.STRICT_CLEAR
				_:
					song_stats.clear_state = SessionManager.SongResult.ClearState.CLEAR
	# I think I want particle effects and stuff to show in the 3D scene, so delay showing
	var beats_to_wait = 8 if not autoblast else 2
	await get_tree().create_timer(beats_to_wait * song_data.seconds_per_beat).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	song_instance.hud.hide()
	result_screen.display(finish_state, song_stats,
		SessionManager.get_song_best_record(midi_hash, difficulty))
	
	if valid_record:
		SessionManager.record_song_result(midi_hash, song_stats)
		#SessionManager.save_song_records()

func _toggle_pause() -> void:
	# Prevent pause if result or fail screen is visible
	if not can_pause:
		return
	
	if not song_instance or not is_instance_valid(song_instance):
		return
	
	get_tree().paused = not get_tree().paused
	pause_panel.visible = get_tree().paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_HIDDEN

func _on_continue_pressed() -> void:
	_toggle_pause()

func _on_restart_pressed() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	pause_panel.hide()
	result_screen.hide()
	# TODO: Add fade out transition here
	if song_instance and is_instance_valid(song_instance):
		song_instance.queue_free()
		await song_instance.tree_exited
	song_instance = SONG_SCENE.instantiate() as SynRoadSong
	song_instance.song_failed.connect(_on_song_failed)
	song_instance.song_finished.connect(_on_song_finished)
	add_child(song_instance)
	await song_instance.song_prepared
	get_tree().paused = false
	await get_tree().process_frame
	song_instance.start_song()
	if not get_window().has_focus():
		_toggle_pause()

func _on_quit_pressed() -> void:
	Transition.start_transition_in()
#	SessionManager.save_campaign_data()
	await Transition.animation_completed
	if get_tree().paused:
		song_instance.get_node("SongPlayer").stop()
		get_tree().paused = false
		get_tree().change_scene_to_file("res://menu/song_select.tscn")
	else:
		var vol_tween = create_tween()
		vol_tween.tween_property(song_instance.get_node("SongPlayer"), "volume_db", -80.0, 1.0)
		await vol_tween.finished
		get_tree().change_scene_to_file("res://menu/song_select.tscn")

func _on_lose_focus():
	if not get_tree().paused:
		_toggle_pause()
