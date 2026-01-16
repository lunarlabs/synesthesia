extends Node
class_name SynRoadSongManager

@export_file("*.tres") var song_file: String
@export_enum("Beginner:96", "Intermediate:102", "Advanced:108", "Expert:114")
var difficulty: int = 96
@export_group("Modifiers")
@export_enum("Normal", "Constant Drain", "No Recover", "Sudden Death", "No Fail") var energy_modifier: int = 0
@export_enum("Normal", "Disabled", "Barrier 2", "Barrier 3", "Barrier 4") var checkpoint_modifier: int = 0
@export var hide_streak_hints: bool = false
@export_enum("Normal", "Loose", "Strict") var timing_modifier: int = 0
@export_enum("Normal:12", "Fast Reset 1:10", "Fast Reset 2:8") var fast_track_reset: int = 12
@export var autoblast: bool = false
@export_range(0.5, 3.0, 0.25) var hi_speed: float = 1.0

var can_pause := false

const SONG_SCENE:PackedScene = preload("res://entities/song.tscn")

const DIFFICULTY_NAMES = {
	96: "Beginner",
	102: "Intermediate",
	108: "Advanced",
	114: "Expert"
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
	8: "Fast Reset 2"
}

const ACCURACY_THRESHOLDS = {
	"AAA": 0.97,
	"AA": 0.93,
	"A": 0.90,
	"B": 0.80,
	"C": 0.70,
	"D": 0.60,
	"E": 0.50,
	"F": 0.00,
}

const STANDARD_LENGTH_PER_BEAT = -4.0
const BEATS_PER_MEASURE = 4.0
const CHUNK_LENGTH_IN_MEASURES = 8
const TIMING_WINDOWS = [0.06, 0.08, 0.04,]
const MISS_WINDOW_OFFSET = 0.01

@onready var pause_panel: PanelContainer = $PausePanel
@onready var btn_continue: Button = $PausePanel/VBoxContainer/ContinueButton
@onready var btn_restart: Button = $PausePanel/VBoxContainer/RestartButton
@onready var btn_quit: Button = $PausePanel/VBoxContainer/QuitButton
@onready var fail_screen: Control = $SongFail
@onready var result_screen: Control = $SongResult

# For this refactor, we'll use time instead of beats for everything
# Also measures will be zero-indexed
var song_data:SongData
var song_instance:SynRoadSong
var preprocessor:SynRoadTrackPreprocessor
var note_maps:Array[Dictionary]
var track_data:Array[Dictionary]
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
var suppressed_measures: Array[bool] = []
var hit_window: float
var miss_window: float

func _ready() -> void:
	get_window().focus_exited.connect(_on_lose_focus)
	print("Loading %s" % song_file)
	song_data = load(song_file) as SongData
	await get_tree().process_frame
	if not song_data:
		push_error("Failed to load song data from %s" % song_file)
		return

	note_maps = _get_note_maps()
	ChunkManager.manager_node = self
	hit_window = TIMING_WINDOWS[timing_modifier]
	miss_window = hit_window + MISS_WINDOW_OFFSET
	seconds_per_beat = song_data.seconds_per_beat
	length_multiplier = (hi_speed) / song_data.scale_fudge_factor
	print ("Length multiplier set to %.3f (Hi-Speed: %.2f, Fudge: %.2f)" % [length_multiplier, hi_speed, song_data.scale_fudge_factor])
	length_per_beat = STANDARD_LENGTH_PER_BEAT * length_multiplier
	ideal_playhead_speed = length_per_beat / seconds_per_beat
	print("Ideal playhead speed: %.3f units/sec" % ideal_playhead_speed)

	total_measures = song_data.lead_in_measures + song_data.playable_measures
	finish_time = total_measures * seconds_per_beat * BEATS_PER_MEASURE
	for i in range(total_measures + 2):
		print("calculate chunk %d" % i)
		measure_times.append(seconds_per_beat * BEATS_PER_MEASURE * i)
		measure_positions.append(i * length_per_beat * BEATS_PER_MEASURE)
		@warning_ignore("integer_division")
		var chunk = i / CHUNK_LENGTH_IN_MEASURES
		measure_in_chunks.append(chunk)
		chunk_count = max(chunk_count, chunk + 1)
	chunk_count += 1

	suppressed_measures.resize(total_measures)
	print ("suppressing checkpoint measures")
	for measure in song_data.checkpoints:
		var actual_measure = measure + song_data.lead_in_measures
		checkpoint_measures.append(actual_measure)
		checkpoint_positions.append(measure_positions[actual_measure])
		match checkpoint_modifier:
			0:
				suppressed_measures[actual_measure] =  true
				suppressed_measures[actual_measure + 1] = true
			1:
				# Disabled -- leave the checkpoint gates as is but they won't do anything
				pass 
			# TODO: Barrier logic.
			2:
				pass
			3:
				pass
			4:
				pass

	track_data.resize(song_data.tracks.size())
	_fetch_track_data()
	preprocessor.wait_for_all()
	var results = preprocessor.take_completed()
	_apply_preprocessor_results(results)
	if track_data.size() == 0:
		push_error("No valid track data found for selected difficulty %d" % difficulty)
		OS.alert("The selected song does not have valid note data for the chosen difficulty. Please select a different difficulty or song.")
		return
	
	# Connect pause menu buttons
	btn_continue.pressed.connect(_on_continue_pressed)
	btn_restart.pressed.connect(_on_restart_pressed)
	btn_quit.pressed.connect(_on_quit_pressed)
	
	# Connect result screen buttons
	var result_exit_btn = result_screen.get_node("%ExitButton") as Button
	var result_restart_btn = result_screen.get_node("%RestartButton") as Button
	result_exit_btn.pressed.connect(_on_quit_pressed)
	result_restart_btn.pressed.connect(_on_restart_pressed)
	
	# Connect fail screen buttons
	var fail_exit_btn = fail_screen.get_node("%ExitButton") as Button
	var fail_restart_btn = fail_screen.get_node("%RestartButton") as Button
	fail_exit_btn.pressed.connect(_on_quit_pressed)
	fail_restart_btn.pressed.connect(_on_restart_pressed)
	
	song_instance = SONG_SCENE.instantiate() as SynRoadSong

	song_instance.song_failed.connect(_on_song_failed)
	song_instance.song_finished.connect(_on_song_finished)
	print ("handing over to song node now")
	add_child.call_deferred(song_instance)

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
			"song_track_index" : i,
			"note_map": note_maps[i],
			"seconds_per_beat": 60.0 / song_data.bpm,
			"chunk_count": chunk_count,
			"suppressed_measures": suppressed_measures,
			"track_reset": fast_track_reset,
			"length_per_beat": length_per_beat,
			"total_measures": total_measures,
		}
		preprocessor.queue_job(job)

func _get_note_maps() -> Array[Dictionary]:
	print ("getting note maps...")
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

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()

func _on_song_failed(stats) -> void:
	var fail_anim = fail_screen.get_node("AnimationPlayer") as AnimationPlayer
	# TODO: the rest of the fail screen labels and then populate them with stats
	# TODO: we have %TipLabel but no tips yet so you'll just see the "no fail" tip all the time
	var percent_completed = (float(stats.measure) / (song_data.playable_measures + song_data.lead_in_measures)) * 100.0
	fail_screen.get_node("%SongTitleLabel").text = song_data.long_title
	fail_screen.get_node("%ArtistLabel").text = song_data.artist
	fail_screen.get_node("%DifficultyLabel").text = DIFFICULTY_NAMES[difficulty]
	fail_screen.get_node("%PercentCompletedLabel").text = "%.2f%%" % percent_completed
	fail_screen.get_node("%ScoreLabel").text = str(stats.score)
	fail_screen.get_node("%StreakLabel").text = str(stats.max_streak)
	var accuracy = (float(stats.phrases_completed) / (stats.phrases_completed + stats.phrases_missed)) * 100.0
	fail_screen.get_node("%AccuracyLabel").text = "%.2f%%" % accuracy
	fail_screen.get_node("%StreakBreakLabel").text = str(stats.streak_breaks)
	# "Song Failed" slams down as soon as the slowdown begins and covers the whole duration
	# of the slowdown effect.
	fail_screen.show()

	fail_anim.play("Display")
	# Enable buttons when animation finishes
	var exit_btn = fail_screen.get_node("%ExitButton") as Button
	var restart_btn = fail_screen.get_node("%RestartButton") as Button
	await fail_anim.animation_finished
	exit_btn.disabled = false
	restart_btn.disabled = false

func _on_song_finished(stats) -> void:
	var song_stats := SessionManager.SongResult.new()
	song_stats.energy_modifier = energy_modifier
	song_stats.checkpoint_modifier = checkpoint_modifier
	song_stats.hide_streak_hints = hide_streak_hints
	song_stats.fast_track_reset = fast_track_reset
	song_stats.score = stats["score"]
	song_stats.max_streak = stats["max_streak"]
	var accuracy = (float(stats.phrases_completed) / (stats.phrases_completed + stats.phrases_missed)) * 100.0
	song_stats.accuracy = accuracy
	song_stats.streak_breaks = stats["streak_breaks"]
	song_stats.percent_completed = 100.0
	song_stats.calculate_rank()

	# I think I want particle effects and stuff to show in the 3D scene, so delay showing
	await get_tree().create_timer(8 * song_data.seconds_per_beat).timeout
	song_instance.hud.hide()
	result_screen.show()
	result_screen.get_node("AnimationPlayer").play("BuildIn")
	# Enable buttons when animation finishes
	var exit_btn = result_screen.get_node("%ExitButton") as Button
	var restart_btn = result_screen.get_node("%RestartButton") as Button
	exit_btn.disabled = false
	restart_btn.disabled = false

func _toggle_pause() -> void:
	# Prevent pause if result or fail screen is visible
	if not can_pause:
		return
	
	if not song_instance or not is_instance_valid(song_instance):
		return
	
	get_tree().paused = not get_tree().paused
	pause_panel.visible = get_tree().paused

func _on_continue_pressed() -> void:
	_toggle_pause()

func _on_restart_pressed() -> void:
	get_tree().paused = false
	pause_panel.hide()
	result_screen.hide()
	fail_screen.hide()
	# TODO: Add fade out transition here
	if song_instance and is_instance_valid(song_instance):
		song_instance.queue_free()
		await song_instance.tree_exited
	song_instance = SONG_SCENE.instantiate() as SynRoadSong
	song_instance.song_failed.connect(_on_song_failed)
	song_instance.song_finished.connect(_on_song_finished)
	add_child(song_instance)
	await get_tree().process_frame
#	song_instance.start_song()

func _on_quit_pressed() -> void:
	get_tree().paused = false
#	SessionManager.save_campaign_data()
	get_tree().change_scene_to_file("res://menu/SongSelect.tscn")

func _on_lose_focus():
	if not get_tree().paused:
		_toggle_pause()
