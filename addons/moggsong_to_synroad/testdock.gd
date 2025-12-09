extends VBoxContainer

var _current_songdata: SongData
var _current_songdata_path: String = ""
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



func _on_folder_select_button_pressed() -> void:
	%SongDirDialog.dir_selected.connect(func(dir_path: String) -> void:
		_current_folder = dir_path
		%SongFolderEdit.text = dir_path
		_current_songdata = _try_load_songdata(dir_path)
		if _current_songdata:
			%StatusLine.text = "Loaded song for %s" % _current_songdata.title
			_populate_gui_from_songdata(_current_songdata)
		else:
			%StatusLine.text = "No SynRoad SongData found in selected folder. Press Import to create a new one."
			_clear_gui()
			%ImportButton.disabled = false
			%SaveButton.disabled = true
	)
	%SongDirDialog.popup_centered()


func _on_import_button_pressed() -> void:
	var songdata_name = _current_folder.get_file()
	var moggsong_path = _current_folder + "/" + songdata_name + ".moggsong"
	var midi_path = _current_folder + "/" + songdata_name + ".mid"
	var midi_result = _read_midi_file(midi_path)
	if midi_result.is_empty():
		%StatusLine.text = "Failed to import MIDI: %s" % midi_result.get("error_message", "Unknown error")
		return
	print(str(midi_result))
	_current_songdata = SongData.new()
	_current_songdata.title = songdata_name
	_current_songdata.long_title = songdata_name
	_current_songdata.fixed_bpm = midi_result.get("bpm", 120.0)
	var track_names: Array[String] = midi_result.get("track_names", [])
	for track_name in track_names:
		if track_name.containsn("catch"):
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
	%StatusLine.text = "Imported MIDI with %d tracks." % _current_songdata.tracks.size()
	_populate_gui_from_songdata(_current_songdata)
	var moggsong_result = _read_moggsong_file(moggsong_path)
	print(str(moggsong_result))
	if moggsong_result.has("error_message"):
		%StatusLine.text += " Failed to import moggsong: %s. Metadata not filled." % moggsong_result["error_message"]
	else:
		_current_songdata.title = moggsong_result.get("title_short", songdata_name)
		_current_songdata.long_title = moggsong_result.get("title", songdata_name)
		_current_songdata.artist = moggsong_result.get("artist", "Unknown Artist")
		_current_songdata.genre = moggsong_result.get("genre", "Unknown Genre")
		_current_songdata.description = moggsong_result.get("desc", "")
		if abs(moggsong_result.get("bpm", 120.0) - _current_songdata.fixed_bpm) > 0.1:
			%StatusLine.text += " Warning: BPM in moggsong (%.1f) differs from MIDI (%.1f)." % [moggsong_result.get("bpm", 120.0), _current_songdata.fixed_bpm]
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
		%StatusLine.text += " Imported moggsong metadata."

func _on_save_button_pressed() -> void:
	pass # Replace with function body.


func _on_add_track_button_pressed() -> void:
	pass # Replace with function body.


func _on_add_checkpoint_button_pressed() -> void:
	pass # Replace with function body.

func _try_load_songdata(folder_path: String) -> SongData:
	var songdata_name = folder_path.get_file()
	_current_songdata_path = folder_path + "/" + songdata_name + ".tres"
	if FileAccess.file_exists(_current_songdata_path):
		return ResourceLoader.load(_current_songdata_path) as SongData
	return null

func _populate_gui_from_songdata(songdata: SongData) -> void:
	%SongTitleEntry.text = songdata.title
	%SongTitleEntry.editable = true
	%LongTitleEntry.text = songdata.long_title
	%LongTitleEntry.editable = true
	%ArtistEntry.text = songdata.artist
	%ArtistEntry.editable = true
	%GenreEntry.text = songdata.genre
	%GenreEntry.editable = true
	%DescEntry.text = songdata.description
	%DescEntry.editable = true
	%FixedBPMTitle.button_pressed = songdata.bpm_fix
	%FixedBPMTitle.disabled = false
	%FixedBPMEntry.value = songdata.fixed_bpm
	%FixedBPMEntry.editable = true
	%IntroMeasuresEntry.value = songdata.lead_in_measures
	%IntroMeasuresEntry.editable = true
	%PlayableMeasuresEntry.value = songdata.playable_measures
	%PlayableMeasuresEntry.editable = true
	%AddTrackButton.disabled = false
	_clear_track_rows()
	for track in songdata.tracks:
		_add_track_row(track)
	%TrackList.queue_sort()
	if songdata.click_track != null:
		%ClickTrackEntry.text = songdata.click_track
	%ClickTrackEntry.editable = true
	%ClickTrackBrowseButton.disabled = false
	%CheckpointList.clear()
	for checkpoint in songdata.checkpoints:
		%CheckpointList.add_item("Measure %d" % checkpoint)
	%AddCheckpointButton.disabled = false
	%CheckpointSpin.value = 4
	%CheckpointSpin.editable = true
	%ImportButton.disabled = true
	%SaveButton.disabled = false

func _clear_gui() -> void:
	%SongTitleEntry.text = ""
	%SongTitleEntry.editable = false
	%LongTitleEntry.text = ""
	%LongTitleEntry.editable = false
	%ArtistEntry.text = ""
	%ArtistEntry.editable = false
	%GenreEntry.text = ""
	%GenreEntry.editable = false
	%DescEntry.text = ""
	%DescEntry.editable = false
	%FixedBPMTitle.button_pressed = false
	%FixedBPMTitle.disabled = true
	%FixedBPMEntry.value = 120.0
	%FixedBPMEntry.editable = false
	%IntroMeasuresEntry.value = 4
	%IntroMeasuresEntry.editable = false
	%PlayableMeasuresEntry.value = 100
	%PlayableMeasuresEntry.editable = false
	%AddTrackButton.disabled = true
	%ClickTrackEntry.text = ""
	%ClickTrackEntry.editable = false
	%ClickTrackBrowseButton.disabled = true
	%CheckpointList.clear()
	%AddCheckpointButton.disabled = true
	%CheckpointSpin.value = 4
	%CheckpointSpin.editable = false
	_clear_track_rows()
	%ImportButton.disabled = true
	%SaveButton.disabled = true

func _clear_track_rows() -> void:
	for child in %TrackList.get_children():
		%TrackList.remove_child(child)
		child.queue_free()

func _add_track_row(trackdata: SongTrackData = null) -> void:
	var row = TrackRow.new(_instrument_options)
	if trackdata:
		row.midi_name.text = trackdata.midi_track_name
		row.instrument.selected = trackdata.instrument
		row.audio.text = trackdata.audio_file
	row.browse.pressed.connect(func(r=row) -> void:
		r.file_dialog.popup_centered()
	)
	row.file_dialog.file_selected.connect(func(path: String, r=row) -> void:
		r.audio.text = path
	)
	row.remove.pressed.connect(func(r=row) -> void:
		%TrackList.remove_child(r.root)
		r.root.queue_free()
	)
	%TrackList.add_child(row.root)
	%TrackList.queue_sort()

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
