## midi_normalize.gd
## @tool script that rewrites all .mid files under res://song/ so that every
## MIDI event has an explicit status byte (no running status compression).
## This is a one-shot fix for godot-midi not supporting running status.
##
## HOW TO USE:
##   1. Open the Godot editor.
##   2. Open this file in the script editor.
##   3. Click File > Run (or press Ctrl+Shift+X).
##   4. Check the Output panel for results.
##   5. Re-import the affected .mid files (or let Godot auto-detect the changes).
@tool
extends EditorScript

const SCAN_ROOT := "res://song"

func _run() -> void:
	print("=== MIDI Running-Status Normalizer ===")
	var files := _find_midi_files(SCAN_ROOT)
	print("Found %d .mid files under %s" % [files.size(), SCAN_ROOT])
	var ok_count := 0
	var err_count := 0
	for path in files:
		print("Processing: %s" % path)
		var result := _normalize_midi_file(path)
		if result == OK:
			ok_count += 1
		else:
			push_error("  FAILED: %s" % path)
			err_count += 1
	print("Done. %d OK, %d errors." % [ok_count, err_count])
	print("Re-import .mid files in the FileSystem dock to apply changes.")

# ── File discovery ────────────────────────────────────────────────────────────

func _find_midi_files(dir_path: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if not dir:
		push_error("Cannot open directory: %s" % dir_path)
		return result
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir() and name != "." and name != "..":
			result.append_array(_find_midi_files(dir_path + "/" + name))
		elif name.get_extension().to_lower() in ["mid", "midi"]:
			result.append(dir_path + "/" + name)
		name = dir.get_next()
	dir.list_dir_end()
	return result

# ── Core normalizer ───────────────────────────────────────────────────────────

func _normalize_midi_file(res_path: String) -> Error:
	var abs_path := ProjectSettings.globalize_path(res_path)

	# Read raw bytes
	var fa := FileAccess.open(res_path, FileAccess.READ)
	if not fa:
		push_error("  Cannot read: %s" % res_path)
		return ERR_FILE_CANT_READ
	var raw := fa.get_buffer(fa.get_length())
	fa.close()

	# Validate MIDI header magic "MThd"
	if raw.size() < 14 or raw[0] != 0x4D or raw[1] != 0x54 or raw[2] != 0x68 or raw[3] != 0x64:
		push_error("  Not a valid MIDI file (bad header)")
		return ERR_FILE_CORRUPT

	var out := PackedByteArray()
	var pos := 0

	# --- MThd header (14 bytes, copy verbatim) ---
	var header_len := _read_u32(raw, 4) # always 6 for standard MIDI
	var chunk_end := 8 + header_len
	out.append_array(raw.slice(0, chunk_end))
	pos = chunk_end

	# --- MTrk chunks ---
	var changed := false
	while pos + 8 <= raw.size():
		# chunk type (4 bytes) + chunk length (4 bytes)
		var chunk_type := raw.slice(pos, pos + 4)
		var chunk_len := _read_u32(raw, pos + 4)
		var chunk_data_start := pos + 8
		var chunk_data_end := chunk_data_start + chunk_len

		if chunk_type[0] != 0x4D or chunk_type[1] != 0x54 or chunk_type[2] != 0x72 or chunk_type[3] != 0x6B:
			# Not "MTrk" — copy verbatim and skip
			out.append_array(raw.slice(pos, chunk_data_end))
			pos = chunk_data_end
			continue

		# Parse and expand running status for this track
		var track_in := raw.slice(chunk_data_start, chunk_data_end)
		var track_out := _expand_running_status(track_in)
		if track_out.size() != track_in.size():
			changed = true

		# Write MTrk + new length + new data
		out.append_array(chunk_type)
		_append_u32(out, track_out.size())
		out.append_array(track_out)
		pos = chunk_data_end

	if not changed:
		print("  No running status found, file unchanged.")
		return OK

	# Write result back
	var fw := FileAccess.open(res_path, FileAccess.WRITE)
	if not fw:
		push_error("  Cannot write: %s" % res_path)
		return ERR_FILE_CANT_WRITE
	fw.store_buffer(out)
	fw.close()
	print("  Expanded running status — file rewritten (%d -> %d bytes)." % [raw.size(), out.size()])
	return OK

# ── Running-status expander ───────────────────────────────────────────────────

func _expand_running_status(track: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	var p := 0
	var last_status: int = 0 # running status register

	while p < track.size():
		# 1. Read variable-length delta time
		var delta_bytes := PackedByteArray()
		var delta_val := 0
		while true:
			if p >= track.size():
				break
			var b := track[p]
			p += 1
			delta_bytes.append(b)
			delta_val = (delta_val << 7) | (b & 0x7F)
			if (b & 0x80) == 0:
				break
		out.append_array(delta_bytes)

		if p >= track.size():
			break

		var status_byte := track[p]

		# 2. Determine the status for this event
		if status_byte == 0xFF:
			# Meta event — clears running status
			last_status = 0
			out.append(track[p]); p += 1 # 0xFF
			out.append(track[p]); p += 1 # meta type
			# variable-length length
			var meta_len := 0
			while true:
				var b := track[p]
				out.append(b); p += 1
				meta_len = (meta_len << 7) | (b & 0x7F)
				if (b & 0x80) == 0:
					break
			# data
			out.append_array(track.slice(p, p + meta_len))
			p += meta_len

		elif status_byte == 0xF0 or status_byte == 0xF7:
			# SysEx — clears running status
			last_status = 0
			out.append(track[p]); p += 1 # F0 / F7
			# variable-length length
			var sx_len := 0
			while true:
				var b := track[p]
				out.append(b); p += 1
				sx_len = (sx_len << 7) | (b & 0x7F)
				if (b & 0x80) == 0:
					break
			out.append_array(track.slice(p, p + sx_len))
			p += sx_len

		elif status_byte >= 0x80:
			# Normal channel message with an explicit status byte
			last_status = status_byte
			out.append(status_byte); p += 1
			# Read remaining data bytes for this message type
			var n := _channel_event_data_bytes(status_byte)
			out.append_array(track.slice(p, p + n))
			p += n

		else:
			# Running status: data byte, no new status — inject the last status
			if last_status == 0:
				push_warning("Running status with no previous status at byte %d — skipping." % p)
				p += 1
				continue
			# Inject explicit status byte
			out.append(last_status)
			# Read data bytes for this message (first data byte is current byte)
			var n := _channel_event_data_bytes(last_status)
			out.append_array(track.slice(p, p + n))
			p += n

	return out

# Returns the number of DATA bytes (after the status byte) for a channel message.
func _channel_event_data_bytes(status: int) -> int:
	match status & 0xF0:
		0x80: return 2 # Note Off
		0x90: return 2 # Note On
		0xA0: return 2 # Aftertouch
		0xB0: return 2 # Control Change
		0xC0: return 1 # Program Change
		0xD0: return 1 # Channel Pressure
		0xE0: return 2 # Pitch Bend
	return 0

# ── Byte helpers ──────────────────────────────────────────────────────────────

func _read_u32(buf: PackedByteArray, offset: int) -> int:
	return (buf[offset] << 24) | (buf[offset + 1] << 16) | (buf[offset + 2] << 8) | buf[offset + 3]

func _append_u32(buf: PackedByteArray, value: int) -> void:
	buf.append((value >> 24) & 0xFF)
	buf.append((value >> 16) & 0xFF)
	buf.append((value >> 8) & 0xFF)
	buf.append(value & 0xFF)
