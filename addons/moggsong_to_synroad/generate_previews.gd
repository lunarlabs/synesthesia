@tool
extends EditorScript

const SCAN_ROOT = "res://song"

func _run() -> void:
	print("=== Preview Generator ===")
	var folders = _find_moggsong_folders(SCAN_ROOT)
	for folder in folders:
		_generate_preview(folder)

func _generate_preview(folder_path: String) -> void:
	print("Generating preview for %s..." % folder_path)
	var dir := DirAccess.open(folder_path)
	if not dir:
		push_error("Cannot open directory: %s" % folder_path)
		return
	var moggsong_path = folder_path + "/%s.moggsong" % folder_path.get_file()
	var tres_path = folder_path + "/%s.tres" % folder_path.get_file()
	if not FileAccess.file_exists(moggsong_path) or not FileAccess.file_exists(tres_path):
		push_error("Cannot open files: %s %s" % [moggsong_path, tres_path])
		return
	var song_data: SongData = load(tres_path)
	if not song_data:
		push_error("Cannot load songdata file: %s" % tres_path)
		return
	if not song_data.click_track or song_data.click_track.is_empty():
		MoggsongParser.update_songdata_tracks(moggsong_path)
	elif not song_data.preview_audio or song_data.preview_audio.is_empty():
		MoggsongParser.generate_preview_audio(moggsong_path, song_data)
	var save_err = ResourceSaver.save(song_data, tres_path)
	if save_err != OK:
		push_error("Failed to save songdata file: %s" % save_err)
	print("Successfully generated preview for %s" % folder_path)

func _find_moggsong_folders(dir_path: String) -> Array[String]:
	var result: Array[String] = []
	var has_moggsong := false
	var dir := DirAccess.open(dir_path)
	if not dir:
		push_error("Cannot open directory: %s" % dir_path)
		return result
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir() and name != "." and name != "..":
			result.append_array(_find_moggsong_folders(dir_path + "/" + name))
		elif not has_moggsong and name.get_extension().to_lower() == "moggsong":
			has_moggsong = true
		name = dir.get_next()
	dir.list_dir_end()
	if has_moggsong:
		result.append(dir_path)
	return result
