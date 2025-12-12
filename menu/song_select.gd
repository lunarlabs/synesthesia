extends Control

const SONG_MANAGER_SCENE = preload("res://menu/SongManager.tscn")
const CATALOG_JSON_PATH = "user://song_catalog.json"
const DIFFICULTY_VALUES = {
	96: "Beginner",
	102: "Intermediate",
	108: "Advanced",
	114: "Expert"
}
const DIFFICULTY_COLORS = {
	96: Color(0.039, 0.6, 0.113),
	102: Color(0.047, 0.2, 0.459),
	108: Color(0.5, 0.5, 0.0),
	114: Color(0.659, 0.065, 0.065)
}
const DIFFICULTY_COLORS_SELECTED = {
	96: Color(0.039, 1.0, 0.188),
	102: Color(0.094, 0.659, 1.0),
	108: Color(1.0, 1.0, 0.157),
	114: Color(1.0, 0.1, 0.1)
}
const DIFFICULTY_UNAVAILABLE_COLOR = Color(0.3, 0.3, 0.3)

const ENERGY_MODIFIER_NAMES: Array[String] = [
	"MOD_ENERGY_NORMAL",
	"MOD_ENERGY_DRAIN",
	"MOD_ENERGY_NORECOVER",
	"MOD_ENERGY_SUDDENDEATH",
	"MOD_ENERGY_NOFAIL"
]

const CHECKPOINT_MODIFIER_NAMES: Array[String] = [
	"MOD_CHECKPOINTS_NORMAL",
	"MOD_CHECKPOINTS_OFF",
	"MOD_CHECKPOINTS_BARRIER2X",
	"MOD_CHECKPOINTS_BARRIER3X",
	"MOD_CHECKPOINTS_BARRIER4X"
]

const TIMING_MODIFIER_NAMES: Array[String] = [
	"MOD_TIMING_NORMAL",
	"MOD_TIMING_LOOSE",
	"MOD_TIMING_STRICT"
]

const RESET_MODIFIER_NAMES: Array[String] = [
	"MOD_RESET_NORMAL",
	"MOD_RESET_FAST1",
	"MOD_RESET_FAST2"
]

const HI_SPEED_MULTS_VAL: Array[float] = [
	0.5,
	0.75,
	1.0,
	1.25,
	1.5,
	1.75,
	2.0,
]

const HI_SPEED_MULTS_STR: Dictionary = {
	0.5: "0.5x",
	0.75: "0.75x",
	1.0: "",
	1.25: "1.25x",
	1.5: "1.5x",
	1.75: "1.75x",
	2.0: "2.0x",
}

@onready var anim = $AnimationPlayer

var selected_song_index: int = 0
var selected_difficulty: int = 102  # Default to Intermediate

var energy_modifier_index: int = 0
var checkpoint_modifier_index: int = 0
var timing_modifier_index: int = 0
var reset_modifier_index: int = 0
var hi_speed_index: int = 2  # Default to 1.0x

# UI References

func _ready():
	var initialized = SongCatalog.is_initialized
	await get_tree().process_frame  # Wait a frame for UI to initialize
	if not initialized:
		%LoadingContainer.visible = true
		if FileAccess.file_exists(CATALOG_JSON_PATH):
			print("Loading song catalog from disk...")
			var error = SongCatalog.load_from_json(CATALOG_JSON_PATH)
			if error:
				print("Failed to load catalog from disk, reloading...")
				SongCatalog.clear_catalog()
				_load_async()
				SongCatalog.save_to_json(CATALOG_JSON_PATH)
		else:
			await _load_async()
			SongCatalog.save_to_json(CATALOG_JSON_PATH)
		%LoadingContainer.visible = false
		if SongCatalog.catalog.is_empty():
			print("No valid songs found!")
			push_error("No valid songs found!")
			%PlayButton.disabled = true
			return
	
	if SessionManager.song_records.is_empty():
		# temporary until we have a splash screen proper
		SessionManager.load_session()
	_populate_song_list()
	_connect_signals()
	selected_difficulty = SessionManager.previous_select_options.get("difficulty", 102)
	energy_modifier_index = SessionManager.previous_select_options.get("energy_modifier_index", 0)
	checkpoint_modifier_index = SessionManager.previous_select_options.get("checkpoint_modifier_index", 0)
	timing_modifier_index = SessionManager.previous_select_options.get("timing_modifier_index", 0)
	reset_modifier_index = SessionManager.previous_select_options.get("reset_modifier_index", 0)
	hi_speed_index = SessionManager.previous_select_options.get("hi_speed_index", 2)
	%EnergyOption.text = tr(ENERGY_MODIFIER_NAMES[energy_modifier_index])
	%CheckpointOption.text = tr(CHECKPOINT_MODIFIER_NAMES[checkpoint_modifier_index])
	%TimingOption.text = tr(TIMING_MODIFIER_NAMES[timing_modifier_index])
	%ResetOption.text = tr(RESET_MODIFIER_NAMES[reset_modifier_index])
	if HI_SPEED_MULTS_VAL[hi_speed_index] == 1.0:
		%HiSpeedOption.text = tr("MOD_HISPEED")
	else:
		%HiSpeedOption.text = tr("MOD_HISPEED") + " " + HI_SPEED_MULTS_STR[HI_SPEED_MULTS_VAL[hi_speed_index]]
	_select_song(SessionManager.previous_select_options.get("song_index", 0))

func _load_async():
	print("Loading song catalog (async)...")
	SongCatalog.start_reload_async()
	await SongCatalog.await_catalog_ready()

func _populate_song_list():
	%SongList.clear()
	for entry in SongCatalog.catalog:
		var display_text = entry.title
		if not entry.files_valid:
			display_text = "[INVALID] " + display_text
		
		%SongList.add_item(display_text)
		
		if not entry.files_valid:
			%SongList.set_item_custom_fg_color(%SongList.item_count - 1, Color.RED)

func _connect_signals():
	%SongList.item_selected.connect(_on_song_selected)
	%PlayButton.pressed.connect(_on_play_pressed)
	
	# Connect difficulty panels
	%BeginnerDifficulty.gui_input.connect(_on_difficulty_clicked.bind(96))
	%IntermediateDifficulty.gui_input.connect(_on_difficulty_clicked.bind(102))
	%AdvancedDifficulty.gui_input.connect(_on_difficulty_clicked.bind(108))
	%ExpertDifficulty.gui_input.connect(_on_difficulty_clicked.bind(114))

func _select_song(index: int):
	if index < 0 or index >= SongCatalog.catalog.size():
		return
	
	selected_song_index = index
	%SongList.select(index)
	
	var entry = SongCatalog.catalog[index]
	
	# Update song info
	%ArtistLabel.text = entry.artist
	%TitleLabel.text = entry.long_title
	%GenreLabel.text = entry.genre
	%TempoLabel.text = "%.0f BPM" % entry.bpm
	
	# Update difficulty panels
	_update_difficulty_panels(entry)
	
	# Enable/disable play button
	%PlayButton.disabled = not entry.files_valid

	anim.play("SongSelected")

func _update_difficulty_panels(entry: SynRoadSongCatalog.SongEntry):
	var panels = {
		96: %BeginnerDifficulty,
		102: %IntermediateDifficulty,
		108: %AdvancedDifficulty,
		114: %ExpertDifficulty
	} 
	# Auto-select first available difficulty if current not available
	if not entry.available_difficulties.has(selected_difficulty):
		if entry.available_difficulties.size() > 0:
			selected_difficulty = entry.available_difficulties[0]
	
	for diff in [96, 102, 108, 114]:
		var panel = panels[diff]
		var rating = entry.difficulty_ratings.get(diff, 0)
		panel.difficulty_value = int(rating)
		panel.selected = (diff == selected_difficulty)
		panel.update()
	
	_update_previous_bests()
		
func _on_song_selected(index: int):
	_select_song(index)

func _on_difficulty_clicked(event: InputEvent, difficulty: int):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var entry = SongCatalog.catalog[selected_song_index]
		if entry.available_difficulties.has(difficulty):
			selected_difficulty = difficulty
			_update_difficulty_panels(entry)

func _on_play_pressed():
	var entry = SongCatalog.catalog[selected_song_index]
	if not entry.files_valid:
		return
	
	# Create song manager instance
	var manager = SONG_MANAGER_SCENE.instantiate()
	manager.song_file = entry.file_path
	manager.difficulty = selected_difficulty
	
	# Apply modifiers
	# TODO: Button cycling and values not implemented yet
	
	manager.energy_modifier = energy_modifier_index
	manager.hi_speed = HI_SPEED_MULTS_VAL[hi_speed_index]
	manager.checkpoint_modifier = checkpoint_modifier_index
	manager.hide_streak_hints = %NoStreakHintButton.button_pressed
	manager.timing_modifier = timing_modifier_index
	manager.fast_track_reset = [12, 10, 8][reset_modifier_index]
	manager.autoblast = %AutoblastButton.button_pressed
	
	#save current session options
	SessionManager.previous_select_options = {
		"song_index": selected_song_index,
		"difficulty": selected_difficulty,
		"energy_modifier_index": energy_modifier_index,
		"checkpoint_modifier_index": checkpoint_modifier_index,
		"timing_modifier_index": timing_modifier_index,
		"reset_modifier_index": reset_modifier_index,
		"hi_speed_index": hi_speed_index,
		"hide_streak_hints": %NoStreakHintButton.button_pressed,
		"autoblast": %AutoblastButton.button_pressed
	}

	# Load the song
	get_tree().root.add_child(manager)
	get_tree().current_scene = manager
	queue_free()

func _input(event: InputEvent):
	if event.is_action_pressed("ui_up"):
		var new_index = max(selected_song_index - 1, 0)
		_select_song(new_index)
	elif event.is_action_pressed("ui_down"):
		var new_index = min(selected_song_index + 1, SongCatalog.catalog.size() - 1)
		_select_song(new_index)
	elif event.is_action_pressed("ui_accept"):
		if not %PlayButton.disabled:
			_on_play_pressed()


# TODO: Theming when values aren't the default

func _on_energy_option_pressed() -> void:
	energy_modifier_index = (energy_modifier_index + 1) % ENERGY_MODIFIER_NAMES.size()
	%EnergyOption.text = tr(ENERGY_MODIFIER_NAMES[energy_modifier_index])


func _on_reset_option_pressed() -> void:
	reset_modifier_index = (reset_modifier_index + 1) % RESET_MODIFIER_NAMES.size()
	%ResetOption.text = tr(RESET_MODIFIER_NAMES[reset_modifier_index])

func _on_hi_speed_option_pressed() -> void:
	hi_speed_index = (hi_speed_index + 1) % HI_SPEED_MULTS_VAL.size()
	if HI_SPEED_MULTS_VAL[hi_speed_index] == 1.0:
		%HiSpeedOption.text = tr("MOD_HISPEED")
	else:
		%HiSpeedOption.text = tr("MOD_HISPEED") + " " + HI_SPEED_MULTS_STR[HI_SPEED_MULTS_VAL[hi_speed_index]]


func _on_checkpoint_option_pressed() -> void:
	checkpoint_modifier_index = (checkpoint_modifier_index + 1) % CHECKPOINT_MODIFIER_NAMES.size()
	%CheckpointOption.text = tr(CHECKPOINT_MODIFIER_NAMES[checkpoint_modifier_index])

func _on_timing_option_pressed() -> void:
	timing_modifier_index = (timing_modifier_index + 1) % TIMING_MODIFIER_NAMES.size()
	%TimingOption.text = tr(TIMING_MODIFIER_NAMES[timing_modifier_index])

func _update_previous_bests():
	var entry = SongCatalog.catalog[selected_song_index]
	if SessionManager.song_records.get(entry.title, {}).get(selected_difficulty, {}).get("clear_state", "not_played") == "not_played":
		%PreviousBestsTitle.text = "MENU_NOTPLAYED"
		%PrevScoreLabel.text = ""
		%PrevRankLabel.text = ""
		%PrevStreakLabel.text = ""
		%PrevAccTitle.text = "MENU_SONGCOMPLETION"
		%PrevAccLabel.text = "0.00%"
	else:
		var record = SessionManager.song_records[entry.title][selected_difficulty]
		%PreviousBestsTitle.text = "MENU_PREV_BESTS" if record["clear_state"] != "failed" else "MENU_FAILED"
		%PrevScoreLabel.text = str(record["score"])
		%PrevRankLabel.text = record.get("rank", "")
		%PrevStreakLabel.text = str(record["max_streak"])
		if record["clear_state"] == "failed":
			%PrevAccTitle.text = "MENU_SONGCOMPLETION"
			%PrevAccLabel.text = "%.2f%%" % (record["percent_completed"])
		else:
			%PrevAccTitle.text = "MENU_PHRASEACCURACYTITLE"
			%PrevAccLabel.text = "%.2f%%" % (record["accuracy"])
