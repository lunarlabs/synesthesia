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

const STANDARD_LENGTH_PER_BEAT = -4.0
const BEATS_PER_MEASURE = 4.0
const CHUNK_LENGTH_IN_MEASURES = 8
const TIMING_WINDOWS = [0.6, 0.8, 0.4,]
const MISS_WINDOW_OFFSET = 0.05

@onready var load_screen: Control = $LoadScreen
@onready var anim: AnimationPlayer = $LoadScreen/AnimationPlayer
@onready var lbl_difficulty: Label = $LoadScreen/StageData/VBoxContainer/TopArea/DifficultyLabel
@onready var song_info: Container = $LoadScreen/SongInfo
@onready var lbl_title: Label = $LoadScreen/SongInfo/TitleLabel
@onready var lbl_artist: Label = $LoadScreen/SongInfo/ArtistLabel
@onready var lbl_genre: Label = $LoadScreen/SongInfo/GenreLabel
@onready var stage_data: Container = $LoadScreen/StageData
@onready var lbl_mod_energy: Label = $LoadScreen/StageData/VBoxContainer/BottomArea/BottomContainer/ModifiersGrid/EnergyModLabel
@onready var lbl_mod_checkpoint: Label = $LoadScreen/StageData/VBoxContainer/BottomArea/BottomContainer/ModifiersGrid/CheckpointModLabel
@onready var lbl_mod_hints: Label = $LoadScreen/StageData/VBoxContainer/BottomArea/BottomContainer/ModifiersGrid/HintsModLabel
@onready var lbl_mod_timing: Label = $LoadScreen/StageData/VBoxContainer/BottomArea/BottomContainer/ModifiersGrid/TimingModLabel
@onready var lbl_track_reset: Label = $LoadScreen/StageData/VBoxContainer/BottomArea/BottomContainer/ModifiersGrid/TrackResetModLabel
@onready var lbl_mod_autoblast: Label = $LoadScreen/StageData/VBoxContainer/BottomArea/BottomContainer/ModifiersGrid/AutoblastModLabel
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
	song_data = load(song_file) as SongData
	await get_tree().process_frame
	if not song_data:
		push_error("Failed to load song data from %s" % song_file)
		return

	ChunkManager.manager_node = self
	ChunkManager.start_if_needed()
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
		measure_times.append(seconds_per_beat * BEATS_PER_MEASURE * i)
		measure_positions.append(i * length_per_beat * BEATS_PER_MEASURE)
		@warning_ignore("integer_division")
		var chunk = i / CHUNK_LENGTH_IN_MEASURES
		measure_in_chunks.append(chunk)
		chunk_count = max(chunk_count, chunk + 1)
	chunk_count += 1

	suppressed_measures.resize(total_measures)
	for measure in song_data.checkpoints:
		var actual_measure = measure + song_data.lead_in_measures
		checkpoint_measures.append(actual_measure)
		checkpoint_positions.append(actual_measure * length_per_beat * BEATS_PER_MEASURE * length_multiplier)
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
	
	if not SessionManager.song_records.has(song_data.title):
		SessionManager.song_records[song_data.title] = {}
	SessionManager.song_records[song_data.title][difficulty] = {
		"clear_state": "not_played",
	}
	song_instance = SONG_SCENE.instantiate() as SynRoadSong

	song_instance.song_failed.connect(_on_song_failed)
	song_instance.song_finished.connect(_on_song_finished)
	add_child.call_deferred(song_instance)

func _populate_load_screen() -> void:
	lbl_difficulty.text = DIFFICULTY_NAMES[difficulty]
	lbl_title.text = song_data.long_title
	lbl_artist.text = song_data.artist
	lbl_genre.text = song_data.genre
	if energy_modifier != 0:
		lbl_mod_energy.theme_type_variation = "EnergyModifier"
		lbl_mod_energy.text = ENERGY_MODIFIER_NAMES[energy_modifier]
	if checkpoint_modifier != 0:
		lbl_mod_checkpoint.theme_type_variation = "CheckpointModifier"
		lbl_mod_checkpoint.text = CHECKPOINT_MODIFIER_NAMES[checkpoint_modifier]
	if timing_modifier != 0:
		lbl_mod_timing.theme_type_variation = "TimingModifier"
		lbl_mod_timing.text = TIMING_MODIFIER_NAMES[timing_modifier]
	if fast_track_reset != 12:
		lbl_track_reset.theme_type_variation = "TimingModifier"
		lbl_track_reset.text = FAST_RESET_NAMES[fast_track_reset]
	if hide_streak_hints:
		lbl_mod_hints.theme_type_variation = "HintModifier"
	if autoblast:
		lbl_mod_autoblast.theme_type_variation = "AutoblastModifier"

func _fetch_track_data() -> void:
	preprocessor = SynRoadTrackPreprocessor.new()
	var midi_data = load(song_data.midi_file) as MidiData
	if not midi_data:
		push_error("Failed to load MIDI data from %s" % song_data.midi_file)
		return
	var ticks_per_beat = midi_data.header.ticks_per_beat
	track_data.resize(song_data.tracks.size())
	for i in song_data.tracks.size():
		var track_info = song_data.tracks[i] as SongTrackData
		var midi_track_idx = song_data.song_track_locations.get(track_info.midi_track_name, -1)
		if midi_track_idx == -1:
			push_error("Track name %s not found in MIDI data." % track_info.midi_track_name)
			continue
		preprocessor.queue_job(self, i, midi_data.tracks[midi_track_idx].events, ticks_per_beat)

func _apply_preprocessor_results(results: Array) -> void:
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
	if not autoblast:
		# Update session record if it's not already clear or better
		match SessionManager.song_records.get(song_data.title, {}).get(difficulty, {}).get("clear_state", "not_played"):
			"not_played":
				SessionManager.song_records[song_data.title][difficulty] = {
					"clear_state": "failed",
					"rank": "F",
					"score": stats.score,
					"max_streak": stats.max_streak,
					"accuracy": accuracy,
					"streak_breaks": stats.streak_breaks,
					"percent_completed": percent_completed
			}
			"failed":
				if SessionManager.song_records[song_data.title][difficulty].get("score", 0) < stats.score:
					SessionManager.song_records[song_data.title][difficulty] = {
						"clear_state": "failed",
						"rank": "F",
						"score": stats.score,
						"max_streak": stats.max_streak,
						"accuracy": accuracy,
						"streak_breaks": stats.streak_breaks,
						"percent_completed": percent_completed
						}
	fail_anim.play("Display")
	# Enable buttons when animation finishes
	var exit_btn = fail_screen.get_node("%ExitButton") as Button
	var restart_btn = fail_screen.get_node("%RestartButton") as Button
	await fail_anim.animation_finished
	exit_btn.disabled = false
	restart_btn.disabled = false

func _on_song_finished(stats) -> void:
	var finish_anim = result_screen.get_node("AnimationPlayer") as AnimationPlayer
	# TODO: the rest of the result screen labels and then populate them with stats
	result_screen.get_node("%SongTitleLabel").text = song_data.long_title
	result_screen.get_node("%ArtistLabel").text = song_data.artist
	result_screen.get_node("%DifficultyLabel").text = DIFFICULTY_NAMES[difficulty]
	result_screen.get_node("%ScoreLabel").text = str(stats.score)
	result_screen.get_node("%StreakLabel").text = str(stats.max_streak)
	var accuracy = (float(stats.phrases_completed) / (stats.phrases_completed + stats.phrases_missed)) * 100.0
	result_screen.get_node("%AccuracyLabel").text = "%.2f%%" % accuracy
	result_screen.get_node("%StreakBreakLabel").text = str(stats.streak_breaks)
	if SessionManager.song_records.get(song_data.title, {}).get(difficulty, {}).get("clear_state", "not_played") != "not_played":
		result_screen.get_node("%PreviousBestsContainer").show()
		result_screen.get_node("%PrevScoreLabel").text = str(SessionManager.song_records[song_data.title][difficulty]["score"])
		result_screen.get_node("%PrevStreakLabel").text = str(SessionManager.song_records[song_data.title][difficulty]["max_streak"])
		result_screen.get_node("%PrevAccLabel").text = "%.2f%%" % SessionManager.song_records[song_data.title][difficulty]["accuracy"]
		result_screen.get_node("%PrevRankLabel").text = SessionManager.song_records[song_data.title][difficulty]["rank"]
		result_screen.get_node("%ScoreDiffLabel").show()
		result_screen.get_node("%ScoreDiffLabel").text = "%+d" % (stats.score - SessionManager.song_records[song_data.title][difficulty]["score"])
		result_screen.get_node("%StreakDiffLabel").show()
		result_screen.get_node("%StreakDiffLabel").text = "%+d" % (stats.max_streak - SessionManager.song_records[song_data.title][difficulty]["max_streak"])
		result_screen.get_node("%AccuracyDiffLabel").show()
		result_screen.get_node("%AccuracyDiffLabel").text = "%+.2f%%" % (accuracy - SessionManager.song_records[song_data.title][difficulty]["accuracy"])
	# TODO: set color for rank label based on rank, currently white for all
	var rank: String
	if autoblast:
		rank = "auto"
	elif stats.streak_breaks == 0:
		rank = "AAA"
	elif accuracy >= 95.0:
		rank = "AA"
	elif accuracy >= 90.0:
		rank = "A"
	elif accuracy >= 80.0:
		rank = "B"
	elif accuracy >= 70.0:
		rank = "C"
	else:
		rank = "D"
	result_screen.get_node("%RankLabel").text = rank

	if not autoblast:
		if stats["miss_count"] == 0:
			if energy_modifier == ENERGY_MODIFIER_NAMES.find("No Fail") or timing_modifier == TIMING_MODIFIER_NAMES.find("Loose"):
				SessionManager.song_records[song_data.title][difficulty]["clear_state"] = "assist perfect run"
				SessionManager.song_records[song_data.title][difficulty]["rank"] = rank + "*"
			else:
				SessionManager.song_records[song_data.title][difficulty]["clear_state"] = "perfect run"
				SessionManager.song_records[song_data.title][difficulty]["rank"] = rank
		elif energy_modifier == ENERGY_MODIFIER_NAMES.find("No Fail") or timing_modifier == TIMING_MODIFIER_NAMES.find("Loose"):
			SessionManager.song_records[song_data.title][difficulty]["clear_state"] = "assist clear"
			SessionManager.song_records[song_data.title][difficulty]["rank"] = rank + "*"
		else:
			SessionManager.song_records[song_data.title][difficulty]["clear_state"] = "clear"
			SessionManager.song_records[song_data.title][difficulty]["rank"] = rank

		SessionManager.song_records[song_data.title][difficulty]["percent_completed"] = 100.0

		if SessionManager.song_records[song_data.title][difficulty].get("score", 0) < stats.score:
			SessionManager.song_records[song_data.title][difficulty]["score"] = stats.score
		
		if SessionManager.song_records[song_data.title][difficulty].get("max_streak", 0) < stats.max_streak:
			SessionManager.song_records[song_data.title][difficulty]["max_streak"] = stats.max_streak
		
		if SessionManager.song_records[song_data.title][difficulty].get("accuracy", 0) < accuracy:
			SessionManager.song_records[song_data.title][difficulty]["accuracy"] = accuracy

		if SessionManager.song_records[song_data.title][difficulty].get("streak_breaks", 9999) > stats.streak_breaks:
			SessionManager.song_records[song_data.title][difficulty]["streak_breaks"] = stats.streak_breaks

	# I think I want particle effects and stuff to show in the 3D scene, so delay showing
	await get_tree().create_timer(8 * song_data.seconds_per_beat).timeout
	song_instance.hud.hide()
	result_screen.show()
	finish_anim.play("Display")
	# Enable buttons when animation finishes
	var exit_btn = result_screen.get_node("%ExitButton") as Button
	var restart_btn = result_screen.get_node("%RestartButton") as Button
	await finish_anim.animation_finished
	exit_btn.disabled = false
	restart_btn.disabled = false

func _toggle_pause() -> void:
	# Prevent pause if result or fail screen is visible
	if result_screen.visible or fail_screen.visible:
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
	load_screen.hide()

func _on_quit_pressed() -> void:
	get_tree().paused = false
	SessionManager.save_campaign_data()
	get_tree().change_scene_to_file("res://menu/SongSelect.tscn")
