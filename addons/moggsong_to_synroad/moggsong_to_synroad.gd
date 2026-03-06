@tool
extends EditorPlugin

var dock: Control
var panel_button: Button

# UI references
var _folder_edit: LineEdit
var _import_btn: Button
var _save_btn: Button
var _warning_label: Label
var _title_edit: LineEdit
var _long_title_edit: LineEdit
var _artist_edit: LineEdit
var _genre_edit: LineEdit
var _desc_edit: TextEdit
var _fixed_bpm_check: CheckBox
var _fixed_bpm_spin: SpinBox
var _intro_measures_spin: SpinBox
var _playable_measures_spin: SpinBox
var _track_list: VBoxContainer
var _add_track_btn: Button
var _checkpoint_spin: SpinBox
var _add_checkpoint_btn: Button
var _checkpoint_list: ItemList

var _current_songdata: SongData
var _current_folder: String = ""
var _current_moggsong_file: String = ""
var _instrument_options: Array[String] = ["DRUMS", "BASS", "GUITAR", "SYNTH", "VOCALS", "FX"]

class TrackRow:
	var root: HBoxContainer
	var midi_name: LineEdit
	var instrument: OptionButton
	var audio: LineEdit
	var browse: Button
	var remove: Button
	var file_dialog: FileDialog
	func _init(options: Array):
		root = HBoxContainer.new()
		midi_name = LineEdit.new()
		midi_name.placeholder_text = "MIDI Track Name"
		root.add_child(midi_name)
		instrument = OptionButton.new()
		for i in range(options.size()):
			instrument.add_item(options[i], i)
		root.add_child(instrument)
		audio = LineEdit.new()
		audio.placeholder_text = "Audio file (.wav)"
		audio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		root.add_child(audio)
		browse = Button.new()
		browse.text = "Browse"
		root.add_child(browse)
		remove = Button.new()
		remove.text = "Remove"
		root.add_child(remove)
		file_dialog = FileDialog.new()
		file_dialog.access = FileDialog.ACCESS_RESOURCES
		file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		file_dialog.filters = PackedStringArray(["*.wav ; Audio Stems"])
		root.add_child(file_dialog)

func _clear_track_rows():
	for child in _track_list.get_children():
		child.queue_free()

func _add_track_row(midi_track_name: String = "", instrument_idx: int = 0, audio_file: String = "") -> TrackRow:
	var row := TrackRow.new(_instrument_options)
	row.midi_name.text = midi_track_name
	row.instrument.select(instrument_idx)
	row.audio.text = audio_file
	_track_list.add_child(row.root)
	# wire browse
	row.browse.pressed.connect(func():
		row.file_dialog.current_dir = _current_folder
		row.file_dialog.popup_centered()
	)
	row.file_dialog.file_selected.connect(func(path: String):
		row.audio.text = path
	)
	# remove row
	row.remove.pressed.connect(func():
		row.root.queue_free()
	)
	return row

func _enable_plugin() -> void:
	# Add autoloads here.
	pass


func _disable_plugin() -> void:
	# Remove autoloads here.
	pass


func _enter_tree() -> void:
	dock = preload("res://addons/moggsong_to_synroad/dock.tscn").instantiate()
	panel_button = add_control_to_bottom_panel(dock, "MoggSong to SynRoad Converter")
	# Cache node references
	_folder_edit = dock.get_node("%SourceEntry")
	_import_btn = dock.get_node("%ImportButton")
	_save_btn = dock.get_node("%SaveButton")
	_warning_label = dock.get_node("%StatusLine")
	_title_edit = dock.get_node("%SongTitleEntry")
	_long_title_edit = dock.get_node("%SubTitleEntry")
	_artist_edit = dock.get_node("%ArtistEntry")
	_genre_edit = dock.get_node("%GenreEntry")
	_desc_edit = dock.get_node("%DescEntry")
	_fixed_bpm_check = dock.get_node("%FixedBPMTitle")
	_fixed_bpm_spin = dock.get_node("%FixedBPMEntry")
	_intro_measures_spin = dock.get_node("%IntroMeasuresEntry")
	_playable_measures_spin = dock.get_node("%PlayableMeasuresEntry")
	_track_list = dock.get_node("%TrackList")
	_add_track_btn = dock.get_node("%AddTrackButton")
	_checkpoint_spin = dock.get_node("%CheckpointSpin")
	_add_checkpoint_btn = dock.get_node("%AddCheckpointButton")
	_checkpoint_list = dock.get_node("%CheckpointList")
	
	# Connect signals
	var _extract_btn = dock.get_node("%ExtractAudioButton")
	_extract_btn.pressed.connect(_on_extract_button_pressed)
	_import_btn.pressed.connect(_on_import_button_pressed)
	_save_btn.pressed.connect(_on_save_button_pressed)
	_add_track_btn.pressed.connect(_on_add_track_button_pressed)
	_add_checkpoint_btn.pressed.connect(_on_add_checkpoint_button_pressed)
	
	panel_button.text = "MoggSong to SynRoad"
	panel_button.tooltip_text = "Convert MoggSong format songs to SynRoad format."
	panel_button.show()

func _exit_tree() -> void:
	panel_button.hide()
	remove_control_from_bottom_panel(dock)
	dock.free()


func _on_import_button_pressed() -> void:
	var song_dir_dialog = dock.get_node("%MoggsongDialog")
	if song_dir_dialog.file_selected.is_connected(_on_moggsong_file_selected):
		song_dir_dialog.file_selected.disconnect(_on_moggsong_file_selected)
	song_dir_dialog.file_selected.connect(_on_moggsong_file_selected, CONNECT_ONE_SHOT)
	song_dir_dialog.popup_centered()

func _on_moggsong_file_selected(path: String) -> void:
	_current_moggsong_file = path
	_current_folder = path.get_base_dir()
	_folder_edit.text = _current_folder
	
	if not FileAccess.file_exists(MoggsongParser.get_songdata_path(path)):
		_current_songdata = MoggsongParser.create_songdata_from_moggsong(path)
		_populate_gui_from_songdata(_current_songdata)
	else:
		_current_songdata = load(MoggsongParser.get_songdata_path(path))
		_populate_gui_from_songdata(_current_songdata)
	dock.get_node("%ExtractAudioButton").disabled = false
	dock.get_node("%AddTrackButton").disabled = false
	dock.get_node("%AddCheckpointButton").disabled = false
	dock.get_node("%SaveButton").disabled = false

func _on_extract_button_pressed() -> void:
	if not _current_songdata:
		_warning_label.text = "No SongData to extract."
		return
	if _current_moggsong_file.is_empty():
		_warning_label.text = "No moggsong file selected. Please import first."
		return
		
	# Save first to ensure the parser finds the latest data and file context
	_on_save_button_pressed()
	
	MoggsongParser.update_songdata_tracks(_current_moggsong_file)
	_populate_gui_from_songdata(_current_songdata)

func _on_save_button_pressed() -> void:
	if not _current_songdata:
		_warning_label.text = "No SongData to save."
		return
	
	# Update songdata from GUI
	_current_songdata.title = _title_edit.text
	_current_songdata.long_title = _long_title_edit.text
	_current_songdata.artist = _artist_edit.text
	_current_songdata.genre = _genre_edit.text
	_current_songdata.description = _desc_edit.text
	_current_songdata.bpm_fix = _fixed_bpm_check.button_pressed
	_current_songdata.fixed_bpm = _fixed_bpm_spin.value
	_current_songdata.lead_in_measures = int(_intro_measures_spin.value)
	_current_songdata.playable_measures = int(_playable_measures_spin.value)
	
	# Update tracks from track rows
	_current_songdata.tracks.clear()
	for child in _track_list.get_children():
		var row_container = child as HBoxContainer
		if not row_container:
			continue
		var midi_name = row_container.get_child(0) as LineEdit
		var instrument = row_container.get_child(1) as OptionButton
		var audio = row_container.get_child(2) as LineEdit
		
		var trackdata = SongTrackData.new()
		trackdata.midi_track_name = midi_name.text
		trackdata.instrument = instrument.selected
		trackdata.audio_file = audio.text
		_current_songdata.tracks.append(trackdata)
	
	var click_track_entry = dock.get_node("%ClickTrackEntry")
	_current_songdata.click_track = click_track_entry.text if click_track_entry.text != "" else null
	
	# Update checkpoints
	_current_songdata.checkpoints.clear()
	for i in range(_checkpoint_list.item_count):
		var text = _checkpoint_list.get_item_text(i)
		var measure = int(text.get_slice(" ", 1))
		_current_songdata.checkpoints.append(measure)
	
	# Save to file
	var songdata_name = _current_folder.get_file()
	var save_path = _current_folder + "/" + songdata_name + ".tres"
	var error = ResourceSaver.save(_current_songdata, save_path)
	if error == OK:
		_warning_label.text = "SongData saved successfully to %s" % save_path
	else:
		_warning_label.text = "Failed to save SongData: %s" % error_string(error)

func _on_add_track_button_pressed() -> void:
	_add_track_row("", 0, "")

func _on_add_checkpoint_button_pressed() -> void:
	var measure = int(_checkpoint_spin.value)
	# Check if checkpoint already exists
	for i in range(_checkpoint_list.item_count):
		var text = _checkpoint_list.get_item_text(i)
		var existing_measure = int(text.get_slice(" ", 1))
		if existing_measure == measure:
			_warning_label.text = "Checkpoint at measure %d already exists." % measure
			return
	
	_checkpoint_list.add_item("Measure %d" % measure)
	_warning_label.text = "Added checkpoint at measure %d" % measure

func _try_load_songdata(folder_path: String) -> SongData:
	var songdata_name = folder_path.get_file()
	var current_songdata_path = folder_path + "/" + songdata_name + ".tres"
	if FileAccess.file_exists(current_songdata_path):
		return ResourceLoader.load(current_songdata_path) as SongData
	return null

func _populate_gui_from_songdata(songdata: SongData) -> void:
	if not songdata:
		_warning_label.text = "ERROR: Failed to load SongData."
		push_error("_populate_gui_from_songdata called with null SongData.")
		return
	_title_edit.text = songdata.title
	_title_edit.editable = true
	_long_title_edit.text = songdata.long_title
	_long_title_edit.editable = true
	_artist_edit.text = songdata.artist
	_artist_edit.editable = true
	_genre_edit.text = songdata.genre
	_genre_edit.editable = true
	_desc_edit.text = songdata.description
	_desc_edit.editable = true
	_fixed_bpm_check.button_pressed = songdata.bpm_fix
	_fixed_bpm_check.disabled = false
	_fixed_bpm_spin.value = songdata.fixed_bpm
	_fixed_bpm_spin.editable = true
	_intro_measures_spin.value = songdata.lead_in_measures
	_intro_measures_spin.editable = true
	_playable_measures_spin.value = songdata.playable_measures
	_playable_measures_spin.editable = true
	_add_track_btn.disabled = false
	_clear_track_rows()
	for track in songdata.tracks:
		_add_track_row(track.midi_track_name, track.instrument, track.audio_file)
	_track_list.queue_sort()
	var click_track_entry = dock.get_node("%ClickTrackEntry")
	var click_track_browse = dock.get_node("%ClickTrackBrowseButton")
	if songdata.click_track != null:
		click_track_entry.text = songdata.click_track
	click_track_entry.editable = true
	click_track_browse.disabled = false
	_checkpoint_list.clear()
	for checkpoint in songdata.checkpoints:
		_checkpoint_list.add_item("Measure %d" % checkpoint)
	_add_checkpoint_btn.disabled = false
	_checkpoint_spin.value = 4
	_checkpoint_spin.editable = true
	_import_btn.disabled = true
	_save_btn.disabled = false

func _clear_gui() -> void:
	_title_edit.text = ""
	_title_edit.editable = false
	_long_title_edit.text = ""
	_long_title_edit.editable = false
	_artist_edit.text = ""
	_artist_edit.editable = false
	_genre_edit.text = ""
	_genre_edit.editable = false
	_desc_edit.text = ""
	_desc_edit.editable = false
	_fixed_bpm_check.button_pressed = false
	_fixed_bpm_check.disabled = true
	_fixed_bpm_spin.value = 120.0
	_fixed_bpm_spin.editable = false
	_intro_measures_spin.value = 4
	_intro_measures_spin.editable = false
	_playable_measures_spin.value = 100
	_playable_measures_spin.editable = false
	_add_track_btn.disabled = true
	var click_track_entry = dock.get_node("%ClickTrackEntry")
	var click_track_browse = dock.get_node("%ClickTrackBrowseButton")
	click_track_entry.text = ""
	click_track_entry.editable = false
	click_track_browse.disabled = true
	_checkpoint_list.clear()
	_add_checkpoint_btn.disabled = true
	_checkpoint_spin.value = 4
	_checkpoint_spin.editable = false
	_clear_track_rows()
	_import_btn.disabled = true
	_save_btn.disabled = true
