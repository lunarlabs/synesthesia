extends RefCounted
class_name MoggsongParser

static func get_songdata_path(moggsong_file: String) -> String:
	return moggsong_file.get_basename() + ".tres"

static func get_folder(moggsong_file: String) -> String:
	return moggsong_file.get_base_dir()

#region SongData functions

static func create_songdata_from_moggsong(moggsong_file: String) -> SongData:
	var folder = get_folder(moggsong_file)
	var songdata_name = folder.get_file()
	print("creating songdata from moggsong file: %s" % moggsong_file)
	var songdata = SongData.new()
	var moggsong_data = _read_moggsong_file(moggsong_file)
	songdata.midi_file = folder + "/" + moggsong_data["midi_path"]
	# Okay, this is frustrating -- in the moggsong files I have, title_short is the same as title.
	# so the sub title will have to be edited in manually.
	songdata.title = moggsong_data.get("title_short", songdata_name)
	songdata.sub_title = moggsong_data.get("title", "")
	songdata.artist = moggsong_data.get("artist", "Unknown Artist")
	songdata.genre = moggsong_data.get("genre", "Unknown Genre")
	var desc_value = moggsong_data.get("desc", "")
	songdata.description = desc_value if typeof(desc_value) == TYPE_STRING else str(desc_value)
	songdata.fixed_bpm = float(moggsong_data.get("bpm", 120.0))
	if abs(songdata.fixed_bpm - songdata.bpm) > 0.01:
		songdata.bpm_fix = true
	songdata.scale_fudge_factor = float(moggsong_data.get("tunnel_scale", 1.0))
	var song_info_slice = moggsong_data.get("song_info", [])
	for i in song_info_slice.size():
		if typeof(song_info_slice[i]) != TYPE_DICTIONARY:
			continue
		var value: Dictionary = song_info_slice[i]
		if value.has("countin"):
			songdata.lead_in_measures = int(value["countin"])
			continue
		if value.has("length"):
			var length_measures = int(value["length"].get_slice(":", 0))
			songdata.playable_measures = length_measures
			continue
	if moggsong_data.has("section_start_bars"):
		var sections = moggsong_data["section_start_bars"] as Array
		songdata.checkpoints.clear()
		for sec in sections:
			songdata.checkpoints.append(int(sec) - 1) # SongData uses 0-based indexing for checkpoints
	# Populate tracks from MIDI directly on the in-memory SongData.
	# update_songdata_tracks() requires the .tres to already be saved, so we
	# call _set_songdata_tracks_from_midi here instead.
	_set_songdata_tracks_from_midi(songdata)
	return songdata

static func update_songdata_tracks(moggsong_file: String):
	if not FileAccess.file_exists(get_songdata_path(moggsong_file)):
		push_error("Songdata file not found: %s" % get_songdata_path(moggsong_file))
		return
	var songdata: SongData = load(get_songdata_path(moggsong_file))
	if songdata.tracks.is_empty():
		_set_songdata_tracks_from_midi(songdata)
	var moggsong_data = _read_moggsong_file(moggsong_file)
	var mogg_file = get_folder(moggsong_file) + "/" + moggsong_data["mogg_path"]
	# We're gonna be slightly stupid here and assume that the order of tracks
	# in the mogg file matches the order of tracks in the midi file.
	var moggsong_tracks = moggsong_data.get("tracks", [])
	var processed_keys: Array[String] = []
	for i in moggsong_tracks.size():
		# Each track in the moggsong_tracks is a dictionary with a single key, which is the track name.
		var key = moggsong_tracks[i].keys()[0]
		var value = moggsong_tracks[i][key] as Array
		print("processing moggsong track %d: %s" % [i, key])
		if key in processed_keys:
			# We need to give this key an unique name.
			var counter = 1
			while key in processed_keys:
				key = "%s_%d" % [key, counter]
				counter += 1
		processed_keys.append(key)
		var output_file = get_folder(moggsong_file) + "/" + key + ".ogg"
		var channels = value[0] as Array
		var audio_destination = value[1] as String
		_convert_mogg_to_stereo_files(mogg_file, output_file, channels)
		if FileAccess.file_exists(output_file):
			if i < songdata.tracks.size() and audio_destination == "event:/SONG_BUS":
				songdata.tracks[i].audio_file = output_file
				print("assigned track %d: %s to %s" % [i, key, output_file])
			elif key == "bg_click":
				songdata.click_track = output_file
				print("assigned click track: %s" % output_file)
		else:
			push_error("Failed to create track %s" % output_file)
	# Save the mutated songdata back to disk so changes are not lost.
	var save_err = ResourceSaver.save(songdata, get_songdata_path(moggsong_file))
	if save_err != OK:
		push_error("update_songdata_tracks: failed to save songdata: %s" % error_string(save_err))

## Populates [param songdata].tracks from the MIDI file referenced by [param songdata].midi_file.
## Works directly on the in-memory SongData object; the caller is responsible for saving.
static func _set_songdata_tracks_from_midi(songdata: SongData) -> void:
	var midi_data = _read_midi_file(songdata.midi_file)
	var track_names: Array[String] = midi_data.get("track_names", [])
	for track_name in track_names:
		if track_name.containsn("catch"):
			var current_track_names = []
			for t in songdata.tracks:
				current_track_names.append(t.midi_track_name)
			if track_name in current_track_names:
				continue # Avoid duplicate tracks
			var trackdata = SongTrackData.new()
			trackdata.midi_track_name = track_name
			# The character following "catch:" indicates the instrument type
			var instr_char = track_name.get_slice(":", 1).to_lower()
			match instr_char[0]:
				"d":
					trackdata.instrument = 0 # Drums
				"b":
					trackdata.instrument = 1 # Bass
				"g":
					trackdata.instrument = 2 # Guitar
				"s":
					trackdata.instrument = 3 # Synth
				"v":
					trackdata.instrument = 4 # Vocals
				"f":
					trackdata.instrument = 5 # FX
				_:
					trackdata.instrument = 0 # Drums (can't find a better match)
			songdata.tracks.append(trackdata)
			print("added track %s" % track_name)

#endregion

#region Import functions
static func _read_midi_file(path: String) -> Dictionary:
	var result: Dictionary = {}
	var midi_data = MidiResource.new()
	var err = midi_data.load_file(path)
	if err != OK:
		result["error_message"] = "Failed to load MIDI data from %s" % path
		return result
	
	var track_names: Array[String] = []
	var bpm: float = 120.0
	
	# MidiResource stores tracks as objects that have an 'events' property which is an Array of Dictionaries
	for i in range(midi_data.tracks.size()):
		var track = midi_data.tracks[i]
		for event in track.events:
			if event.get("type") == "meta":
				var subtype = event.get("subtype")
				if subtype == 3: # Track Name
					track_names.append(event.get("data", ""))
					break
				elif subtype == 81: # Tempo (0x51)
					var microseconds_per_quarter = float(event.get("data", 500000))
					if microseconds_per_quarter > 0:
						bpm = 60_000_000.0 / microseconds_per_quarter
						
	result["track_names"] = track_names
	result["bpm"] = bpm
	return result

# ===== Multi-channel ogg conversion =====

static func _convert_mogg_to_stereo_files(in_file: String, out_file: String, channels: Array):
	var ffmpeg_path = "ffmpeg"
	# Check if ffmpeg is in path
	var output = []
	var exit_code = OS.execute(ffmpeg_path, ["-version"], output)
	if exit_code != 0:
		# Try common Windows path
		ffmpeg_path = "C:/Program Files/ffmpeg/bin/ffmpeg.exe"
		exit_code = OS.execute(ffmpeg_path, ["-version"], output)
		if exit_code != 0:
			push_error("ffmpeg not found. Please install ffmpeg and add it to your system PATH.")
			return
	
	print("Using ffmpeg at: %s" % ffmpeg_path)

	var stdout := []
	var filter := ""
	match channels.size():
		1:
			# Extract single channel as mono using pan filter
			# MOGG files have all channels in one stream, not separate streams
			filter = '[0:a]pan=mono|c0=c%d[a]' % int(channels[0])
		2:
			# Extract two channels and merge to stereo using pan filter
			filter = '[0:a]pan=stereo|c0=c%d|c1=c%d[a]' % [int(channels[0]), int(channels[1])]
		_:
			print("Unsupported number of channels: %d" % channels.size())
			return
	
	var global_in = ProjectSettings.globalize_path(in_file)
	var global_out = ProjectSettings.globalize_path(out_file)
	
	# Build params array
	# -f ogg forces ffmpeg to treat .mogg as ogg format
	# -y automatically overwrites existing files
	# -filter_complex and filter expression must be separate arguments
	var params := ["-y", "-f", "ogg", "-i", global_in, "-filter_complex", filter, "-map", "[a]", global_out]
	
	print("Running ffmpeg with params: " + str(params))
	exit_code = OS.execute(ffmpeg_path, params, stdout, true)
	print(stdout)
	if exit_code != 0:
		print("Failed to extract %s to %s" % [in_file, out_file])
		push_error("ffmpeg returned %d" % exit_code)
		return
	print("Successfully extracted %s to %s" % [in_file, out_file])

static func _read_moggsong_file(path: String) -> Dictionary:
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
static var _ms_tokens: Array = []
static var _ms_pos: int = 0

static func _moggsong_tokenize(text: String) -> Array[String]:
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

static func _moggsong_parse(tokens: Array) -> Array:
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

static func _moggsong_parse_list() -> Array:
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

static func _moggsong_convert_token(tok: String):
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

static func _moggsong_list_to_structure(lst: Array):
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

static func _moggsong_sequence_to_structure(seq: Array):
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

static func _moggsong_value_to_structure(v):
	if typeof(v) == TYPE_ARRAY:
		return _moggsong_list_to_structure(v)
	return v
#endregion
