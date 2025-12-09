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
	_folder_edit = dock.get_node("%SongFolderEdit")
	_import_btn = dock.get_node("%ImportButton")
	_save_btn = dock.get_node("%SaveButton")
	_warning_label = dock.get_node("%StatusLine")
	_title_edit = dock.get_node("%SongTitleEntry")
	_long_title_edit = dock.get_node("%LongTitleEntry")
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
	var folder_select_btn = dock.get_node("%FolderSelectButton")
	folder_select_btn.pressed.connect(_on_folder_select_button_pressed)
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

func _on_folder_select_button_pressed() -> void:
	var song_dir_dialog = dock.get_node("%SongDirDialog")
	song_dir_dialog.dir_selected.connect(func(dir_path: String) -> void:
		_current_folder = dir_path
		_folder_edit.text = dir_path
		_current_songdata = _try_load_songdata(dir_path)
		if _current_songdata:
			_warning_label.text = "Loaded song for %s" % _current_songdata.title
			_populate_gui_from_songdata(_current_songdata)
		else:
			_warning_label.text = "No SynRoad SongData found in selected folder. Press Import to create a new one."
			_clear_gui()
			_import_btn.disabled = false
			_save_btn.disabled = true
	)
	song_dir_dialog.popup_centered()

func _on_import_button_pressed() -> void:
	var songdata_name = _current_folder.get_file()
	var moggsong_path = _current_folder + "/" + songdata_name + ".moggsong"
	var midi_path = _current_folder + "/" + songdata_name + ".mid"
	var midi_result = _read_midi_file(midi_path)
	if midi_result.is_empty():
		_warning_label.text = "Failed to import MIDI: %s" % midi_result.get("error_message", "Unknown error")
		return
	print(str(midi_result))
	_current_songdata = SongData.new()
	_current_songdata.title = songdata_name
	_current_songdata.midi_file = midi_path
	_current_songdata.long_title = songdata_name
	_current_songdata.fixed_bpm = midi_result.get("bpm", 120.0)
	var track_names: Array[String] = midi_result.get("track_names", [])
	for track_name in track_names:
		if track_name.containsn("catch"):
			var current_track_names = []
			for t in _current_songdata.tracks:
				current_track_names.append(t.midi_track_name)
			if track_name in current_track_names:
				continue  # Avoid duplicate tracks
			var trackdata = SongTrackData.new()
			trackdata.midi_track_name = track_name
			# The character following "catch:" indicates the instrument type
			var instr_char = track_name.get_slice(":", 1).to_lower()
			match instr_char[0]:
				"d":
					trackdata.instrument = 0  # Drums
				"b":
					trackdata.instrument = 1  # Bass
				"g":
					trackdata.instrument = 2  # Guitar
				"s":
					trackdata.instrument = 3  # Synth
				"v":
					trackdata.instrument = 4  # Vocals
				"f":
					trackdata.instrument = 5  # FX
				_:
					trackdata.instrument = 0  # Drums (can't find a better match)
			_current_songdata.tracks.append(trackdata)
	_warning_label.text = "Imported MIDI with %d tracks." % _current_songdata.tracks.size()
	_populate_gui_from_songdata(_current_songdata)
	var moggsong_result = _read_moggsong_file(moggsong_path)
	print(str(moggsong_result))
	if moggsong_result.has("error_message"):
		_warning_label.text += " Failed to import moggsong: %s. Metadata not filled." % moggsong_result["error_message"]
	else:
		_current_songdata.title = moggsong_result.get("title_short", songdata_name)
		_current_songdata.long_title = moggsong_result.get("title", songdata_name)
		_current_songdata.artist = moggsong_result.get("artist", "Unknown Artist")
		_current_songdata.genre = moggsong_result.get("genre", "Unknown Genre")
		_current_songdata.description = moggsong_result.get("desc", "")
		if abs(moggsong_result.get("bpm", 120.0) - _current_songdata.fixed_bpm) > 0.1:
			_warning_label.text += " Warning: BPM in moggsong (%.1f) differs from MIDI (%.1f)." % [moggsong_result.get("bpm", 120.0), _current_songdata.fixed_bpm]
			_current_songdata.bpm_fix = true
			_current_songdata.fixed_bpm = moggsong_result.get("bpm", 120.0)
		var song_info_slice = moggsong_result.get("song_info", [])
		for i in song_info_slice.size():
			var value = song_info_slice[i] as Dictionary
			if value.has("countin"):
				_current_songdata.lead_in_measures = int(value["countin"])
				continue
			if value.has("length"):
				var length_measures = int(value["length"].get_slice(":", 0))
				_current_songdata.playable_measures = length_measures
				continue
		if moggsong_result.has("section_start_bars"):
			var sections = moggsong_result["section_start_bars"] as Array
			_current_songdata.checkpoints = []
			for sec in sections:
				_current_songdata.checkpoints.append(int(sec))
		_populate_gui_from_songdata(_current_songdata)
		_warning_label.text += " Imported moggsong metadata."

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

## IMPORT FUNCTIONS GO HERE ##
func _read_midi_file(path: String) -> Dictionary:
	var result: Dictionary = {}
	var midi_data = load(path) as MidiData
	if not midi_data:
		result["error_message"] = "Failed to load MIDI data from %s" % path
		return result
	
	var track_names: Array[String] = []
	var bpm: float = 120.0
	for i in range(midi_data.tracks.size()):
		var track = midi_data.tracks[i] as MidiData.Track
		for event in track.events:
			if event is MidiData.TrackName:
				track_names.append(event.text)
			elif event is MidiData.Tempo:
				bpm = event.bpm
	result["track_names"] = track_names
	result["bpm"] = bpm
	return result

func _read_moggsong_file(path: String) -> Dictionary:
	# The moggsong file format looks like a kind of dictionary
	# At the top level, the first entry between a pair of parens is the key, which is an unquoted string
	# If there's only two entries, the second is the value, which can be a string (quoted), number, or boolean
	# If there's more than two entries, the value is a nested dictionary or array
	# If a value is a nested dictionary, it's enclosed in parens and may not have a key (use Array).
	# A semicolon indicates a comment to the end of the line.
	var result: Dictionary = {}

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		var error: Error = file.get_open_error()
		result["error_message"] = "Failed to open moggsong file: %s" % str(error)
		return result

	var content: String = file.get_as_text()
	file.close()

	# Strip comments
	var cleaned := ""
	for line in content.split("\n"):
		var semi := line.find(";")
		if semi >= 0:
			cleaned += line.left(semi) + "\n"
		else:
			cleaned += line + "\n"

	# 2) Tokenize and parse
	var tokens: Array[String] = _moggsong_tokenize(cleaned)
	var nested_lists: Array = _moggsong_parse(tokens)
	var final_dict := {}
	for item in nested_lists:
		var structured = _moggsong_list_to_structure(item)
		if typeof(structured) == TYPE_DICTIONARY:
			for k in structured.keys():
				final_dict[k] = structured[k]
		else:
			if not final_dict.has("_root"):
				final_dict["_root"] = []
			final_dict["_root"].append(structured)

	return final_dict

# ===== Moggsong parsing helpers =====
var _ms_tokens: Array = []
var _ms_pos: int = 0

func _moggsong_tokenize(text: String) -> Array[String]:
	var tokens: Array[String] = []
	var i := 0
	while i < text.length():
		var ch := text[i]
		if ch == "(" or ch == ")":
			tokens.append(ch)
			i += 1
		elif ch == '"':
			var j := i + 1
			var sb := ""
			var escaped := false
			while j < text.length():
				var cj := text[j]
				if escaped:
					sb += cj
					escaped = false
				elif cj == "\\":
					escaped = true
				elif cj == '"':
					break
				else:
					sb += cj
				j += 1
			tokens.append('"' + sb + '"')
			i = j + 1
		elif ch == " " or ch == "\t" or ch == "\n" or ch == "\r":
			i += 1
		else:
			var j2 := i
			while j2 < text.length():
				var c2 := text[j2]
				if c2 == " " or c2 == "\t" or c2 == "\n" or c2 == "\r" or c2 == "(" or c2 == ")":
					break
				j2 += 1
			var tok := text.substr(i, j2 - i)
			tokens.append(tok)
			i = j2
	return tokens

func _moggsong_parse(tokens: Array) -> Array:
	_ms_tokens = tokens
	_ms_pos = 0
	var items: Array = []
	while _ms_pos < _ms_tokens.size():
		if _ms_tokens[_ms_pos] == "(":
			_ms_pos += 1
			items.append(_moggsong_parse_list())
		else:
			_ms_pos += 1
	return items

func _moggsong_parse_list() -> Array:
	var lst: Array = []
	while _ms_pos < _ms_tokens.size():
		var t: Variant = _ms_tokens[_ms_pos]
		if t == ")":
			_ms_pos += 1
			break
		elif t == "(":
			_ms_pos += 1
			lst.append(_moggsong_parse_list())
		else:
			lst.append(_moggsong_convert_token(t))
			_ms_pos += 1
	return lst

func _moggsong_convert_token(tok: String):
	if tok.begins_with('"') and tok.ends_with('"'):
		return tok.substr(1, tok.length() - 2)
	var lower := tok.to_lower()
	if lower == "true":
		return true
	elif lower == "false":
		return false
	var is_num := true
	var has_dot := false
	for c in tok:
		if c == ".":
			has_dot = true
		elif not ((c >= "0" and c <= "9") or c == "-" or c == "+"):
			is_num = false
			break
	if is_num:
		if has_dot:
			return float(tok)
		else:
			return int(tok)
	return tok

func _moggsong_list_to_structure(lst: Array):
	if lst.size() == 0:
		return []
	if lst.size() == 2 and typeof(lst[0]) == TYPE_STRING:
		var v = lst[1]
		return {lst[0]: _moggsong_value_to_structure(v)}
	if lst.size() > 2 and typeof(lst[0]) == TYPE_STRING:
		var key: String = lst[0]
		var rest := lst.slice(1, lst.size())
		var structured: Variant = _moggsong_sequence_to_structure(rest)
		return {key: structured}
	var arr: Array = []
	for item in lst:
		arr.append(_moggsong_value_to_structure(item))
	return arr

func _moggsong_sequence_to_structure(seq: Array):
	var i := 0
	var dict_candidate := true
	while i < seq.size():
		var k = seq[i]
		var v = null
		if i + 1 < seq.size():
			v = seq[i + 1]
		if typeof(k) != TYPE_STRING or v == null:
			dict_candidate = false
			break
		i += 2
	if dict_candidate:
		var d: Dictionary = {}
		var j := 0
		while j < seq.size():
			var kk = seq[j]
			var vv = seq[j + 1]
			d[kk] = _moggsong_value_to_structure(vv)
			j += 2
		return d
	var a: Array = []
	for it in seq:
		a.append(_moggsong_value_to_structure(it))
	return a

func _moggsong_value_to_structure(v):
	if typeof(v) == TYPE_ARRAY:
		return _moggsong_list_to_structure(v)
	return v
