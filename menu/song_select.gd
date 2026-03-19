extends Control

const SONG_MANAGER_SCENE = preload("res://menu/SongManager.tscn")
const DIFFICULTY_VALUES = {
	96: "Beginner",
	102: "Basic",
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
	1.0,
	1.25,
	1.5,
	1.75,
	2.0,
	0.5,
	0.75,
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

var subscreen_buttons: Array = []
var bpm_tween: Tween
var prev_bpm: float

var default_cover_art = preload("res://assets/textures/generic_song.svg")

var song_info: Dictionary = {}
var selected_song_folder_id: String
var selected_song_index: int = 0
var available_difficulties := []
var selected_difficulty: int = 102 # Default to Intermediate
var held_difficulty: int = 102

var energy_modifier_index: int = 0
var checkpoint_modifier_index: int = 0
var timing_modifier_index: int = 0
var reset_modifier_index: int = 0
var hi_speed_index: int = 0 # Default to 1.0x

signal difficulty_changed(difficulty: int)


# UI References

func _ready():
	subscreen_buttons = $SubScreenContainer/SubScreenButtons.get_children()
	await get_tree().process_frame # Wait a frame for UI to initialize
	# SongCatalog.scan_for_songs() <- handled in ingest.gd now
	if SongCatalog.song_catalog.is_empty():
		print("No valid songs found!")
		push_error("No valid songs found!")
		%PlayButton.disabled = true
		return
	else:
		print("Song catalog generated with %d songs." % SongCatalog.song_catalog.size())
	_connect_signals()
	# Because carousel's _current_difficulty mirrors selected_difficulty here, we can just let
	# it handle the difficulty state. Nifty!
	$Carousel.restore_state_from_session()
	selected_difficulty = SessionManager.previous_select_options.get(&"difficulty", 102)
	held_difficulty = selected_difficulty
	_select_difficulty(selected_difficulty)
	$Carousel.update_carousel()
	# TODO: replace with new mod select screen crap -- getting rid of the old modifier buttons
	# on the song select screen
	energy_modifier_index = SessionManager.previous_select_options.get("energy_modifier_index", 0)
	checkpoint_modifier_index = SessionManager.previous_select_options.get("checkpoint_modifier_index", 0)
	timing_modifier_index = SessionManager.previous_select_options.get("timing_modifier_index", 0)
	reset_modifier_index = SessionManager.previous_select_options.get("reset_modifier_index", 0)
	hi_speed_index = SessionManager.previous_select_options.get("hi_speed_index", 0)
	%EnergyOption.text = tr(ENERGY_MODIFIER_NAMES[energy_modifier_index])
	%CheckpointOption.text = tr(CHECKPOINT_MODIFIER_NAMES[checkpoint_modifier_index])
	%TimingOption.text = tr(TIMING_MODIFIER_NAMES[timing_modifier_index])
	%ResetOption.text = tr(RESET_MODIFIER_NAMES[reset_modifier_index])
	if HI_SPEED_MULTS_VAL[hi_speed_index] == 1.0:
		%HiSpeedOption.text = tr("MOD_HISPEED")
	else:
		%HiSpeedOption.text = tr("MOD_HISPEED") + " " + HI_SPEED_MULTS_STR[HI_SPEED_MULTS_VAL[hi_speed_index]]
	

func _load_async():
	print("Loading song catalog (async)...")
	SongCatalog.start_reload_async()
	await SongCatalog.await_catalog_ready()

func _connect_signals():
	# Connect difficulty panels
	%BeginnerDifficulty.gui_input.connect(_on_difficulty_clicked.bind(96))
	%IntermediateDifficulty.gui_input.connect(_on_difficulty_clicked.bind(102))
	%AdvancedDifficulty.gui_input.connect(_on_difficulty_clicked.bind(108))
	%ExpertDifficulty.gui_input.connect(_on_difficulty_clicked.bind(114))

	# TODO: connect subscreen buttons to actually open the subscreen

func _select_song(index: int):
	if index < 0 or index >= SongCatalog.song_catalog.size():
		return
	
	var entry = SongCatalog.song_catalog[index]
	
	# Update song info
	%ArtistLabel.text = entry.artist
	%TitleLabel.text = "%s %s" % [entry.title, entry.sub_title] if entry.sub_title else entry.title
	%GenreLabel.text = entry.genre
	%TempoLabel.text = "%.0f BPM" % entry.bpm
	
	# Update difficulty panels
	_update_difficulty_panels(entry)

func _update_tempo_level(value: float):
	%TempoLabel.text = "%.0f BPM" % value
	prev_bpm = value

func _slide_difficulty(offset: int):
	var index = available_difficulties.find(selected_difficulty)
	if index >= 0:
		_select_difficulty(available_difficulties[clampi(index + offset,
		 0, available_difficulties.size() - 1)])

func _update_difficulty_panels(difficulties: Dictionary):
	available_difficulties = difficulties.keys()
	# Auto-select first available difficulty if current not available
	if not available_difficulties.has(selected_difficulty):
		if available_difficulties.size() > 0:
			selected_difficulty = available_difficulties[0]

	for diff in [96, 102, 108, 114]:
		var panels = {
			96: %BeginnerDifficulty,
			102: %IntermediateDifficulty,
			108: %AdvancedDifficulty,
			114: %ExpertDifficulty
		}
		var panel = panels[diff]
		if difficulties.has(diff):
			var rating = difficulties[diff]
			panel.update(rating)
			panel.selected = (diff == selected_difficulty)
		else:
			panel.update()
	if selected_difficulty == held_difficulty:
		difficulty_changed.emit(selected_difficulty)
	_update_previous_bests()

func _select_difficulty(value: int):
	var panels = {
		96: %BeginnerDifficulty,
		102: %IntermediateDifficulty,
		108: %AdvancedDifficulty,
		114: %ExpertDifficulty
	}
	if available_difficulties.has(value) and value != selected_difficulty:
		selected_difficulty = value
		held_difficulty = value
		difficulty_changed.emit(value)
		for diff in [96, 102, 108, 114]:
			panels[diff].selected = (diff == selected_difficulty)
	_update_previous_bests()

func _on_song_selected(index: int):
	_select_song(index)

func _on_difficulty_clicked(event: InputEvent, difficulty: int):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_difficulty(difficulty)

#func _input(event: InputEvent):
	#if event.is_action_pressed("ui_up"):
		#var new_index = max(selected_song_index - 1, 0)
		#_select_song(new_index)
	#elif event.is_action_pressed("ui_down"):
		#var new_index = min(selected_song_index + 1, SongCatalog.catalog.size() - 1)
		#_select_song(new_index)
	#elif event.is_action_pressed("ui_accept"):
		#if not %PlayButton.disabled:
			#_on_play_pressed()
func _unhandled_input(event: InputEvent):
	if get_viewport().gui_get_focus_owner() in subscreen_buttons:
		return
	if event.is_action_pressed("ui_left"):
		get_viewport().set_input_as_handled()
		_slide_difficulty(-1)
	elif event.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()
		_slide_difficulty(1)

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
	if not song_info or song_info.is_empty():
		return
	var record = SessionManager.get_song_best_record(song_info.midi_hash, selected_difficulty)
	if not record or record.clear_state == SessionManager.SongResult.ClearState.NOT_PLAYED:
		%PrevClearLabel.text = "MENU_NOTPLAYED"
		%PrevScoreLabel.text = ""
		%PrevRankLabel.text = "--"
		%PrevStreakLabel.text = ""
		%PrevAccTitle.text = "MENU_SONGCOMPLETION"
		%PrevAccLabel.text = "0.00%"
	else:
		%PrevClearLabel.text = record.get_clear_string(true)
		%PrevRankLabel.text = record.get_rank_string()
		%PrevStreakLabel.text = str(record.max_streak)
		%PrevScoreLabel.text = str(record.score)
		if record.clear_state == SessionManager.SongResult.ClearState.FAILED:
			%PrevAccTitle.text = "MENU_SONGCOMPLETION"
			%PrevAccLabel.text = "%.2f%%" % (record.percent_completed)
		else:
			%PrevAccTitle.text = "MENU_PHRASEACCURACYTITLE"
			%PrevAccLabel.text = "%.2f%%" % (record.accuracy)


func _on_carousel_selection_changed(reference: Dictionary) -> void:
	if bpm_tween:
		bpm_tween.kill()
	%AnimationPlayer.stop()
	match reference[&"type"]:
		&"song_all_difficulties":
			%TitleLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			%GenreLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			song_info = SongCatalog.get_song_info(reference[&"folder_id"])
			if song_info[&"cover_art"]:
				var img = Image.create_from_data(
					song_info[&"cover_art_width"],
					song_info[&"cover_art_height"],
					false,
					song_info[&"cover_art_fmt"],
					song_info[&"cover_art"])
				%CoverArt.texture = ImageTexture.create_from_image(img)
			else:
				%CoverArt.texture = default_cover_art
			%CoverArt.show()
			%ArtistLabel.show()
			%ArtistLabel.text = song_info.artist
			%TitleLabel.text = "%s %s" % [song_info.title, song_info.sub_title] if song_info.sub_title else song_info.title
			%GenreLabel.text = song_info.genre
			%TempoLabel.show()
			bpm_tween = create_tween()
			bpm_tween.tween_method(_update_tempo_level, prev_bpm, song_info.bpm, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			%DifficultyContainer.show()
			%PrevBestContainer.show()
			_update_previous_bests()
			selected_difficulty = held_difficulty
			_update_difficulty_panels(reference[&"difficulties"])
			%AnimationPlayer.play("select_item")

		&"song_single_difficulty":
			%TitleLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			%GenreLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			song_info = SongCatalog.get_song_info(reference[&"folder_id"])
			if song_info[&"cover_art"]:
				var img = Image.create_from_data(
					song_info[&"cover_art_width"],
					song_info[&"cover_art_height"],
					false,
					song_info[&"cover_art_fmt"],
					song_info[&"cover_art"])
				%CoverArt.texture = ImageTexture.create_from_image(img)
			else:
				%CoverArt.texture = default_cover_art
			%CoverArt.show()
			%ArtistLabel.show()
			%ArtistLabel.text = song_info.artist
			%TitleLabel.text = "%s %s" % [song_info.title, song_info.sub_title] if song_info.sub_title else song_info.title
			%GenreLabel.text = song_info.genre
			%TempoLabel.show()
			bpm_tween = create_tween()
			bpm_tween.tween_method(_update_tempo_level, prev_bpm, song_info.bpm, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			%DifficultyContainer.show()
			%PrevBestContainer.show()
			_update_previous_bests()
			_update_difficulty_panels({reference[&"difficulty_offset"]: reference[&"difficulty_rating"]})
			%AnimationPlayer.play("select_item")

		&"submenu":
			available_difficulties.clear()
			prev_bpm = 0
			%ArtistLabel.hide()
			%TempoLabel.hide()
			%DifficultyContainer.hide()
			%PrevBestContainer.hide()
			%CoverArt.hide()
			%TitleLabel.text = reference[&"name"].to_upper()
			%TitleLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			%GenreLabel.text = "Category Select"
			%GenreLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			%AnimationPlayer.play("select_item")

		&"category":
			available_difficulties.clear()
			prev_bpm = 0
			%ArtistLabel.hide()
			%TempoLabel.hide()
			%DifficultyContainer.hide()
			%PrevBestContainer.hide()
			%CoverArt.hide()
			%TitleLabel.text = reference[&"name"].to_upper()
			%TitleLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			%GenreLabel.text = "Folder"
			%GenreLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			%AnimationPlayer.play("select_item")

func _on_carousel_song_selected(song_folder: String, difficulty: int = -1) -> void:
	var manager = SONG_MANAGER_SCENE.instantiate()
	var entry = SongCatalog.get_song_info(song_folder)
	manager.song_file = SongCatalog.get_resource_path(entry.folder_id)
	manager.difficulty = selected_difficulty if difficulty == -1 else difficulty
	manager.resource_hash = entry.resource_hash
	manager.midi_hash = entry.midi_hash

	# Apply modifiers
	# TODO: Button cycling and values not implemented yet

	manager.energy_modifier = energy_modifier_index
	manager.hi_speed = HI_SPEED_MULTS_VAL[hi_speed_index]
	manager.checkpoint_modifier = checkpoint_modifier_index
	manager.hide_streak_hints = %NoStreakHintButton.button_pressed
	manager.timing_modifier = timing_modifier_index
	manager.fast_track_reset = [12, 10, 8][reset_modifier_index]
	manager.autoblast = %AutoblastButton.button_pressed

	# Save current session options so returning to song select restores state correctly
	SessionManager.previous_select_options = {
		"song_index": selected_song_index,
		"difficulty": selected_difficulty if difficulty == -1 else difficulty,
		"energy_modifier_index": energy_modifier_index,
		"checkpoint_modifier_index": checkpoint_modifier_index,
		"timing_modifier_index": timing_modifier_index,
		"reset_modifier_index": reset_modifier_index,
		"hi_speed_index": hi_speed_index,
		"hide_streak_hints": %NoStreakHintButton.button_pressed,
		"autoblast": %AutoblastButton.button_pressed
	}

	# TODO: call transition handler here so there's no loading lag

	# Load the song
	get_tree().root.add_child(manager)
	get_tree().current_scene = manager
	queue_free()


func _on_modifier_button_pressed() -> void:
	for button in subscreen_buttons:
		button.disabled = true
