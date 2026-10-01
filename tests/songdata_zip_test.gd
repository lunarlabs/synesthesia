@tool
extends EditorScript

func _run() -> void:
	var test_name := "songdata_zip_test_%d" % Time.get_ticks_usec()
	var test_root := "user://" + test_name
	var zip_path := test_root.path_join(test_name + ".zip")
	var imported_root := "user://songs/" + test_name
	var fixture_path := test_root.path_join("fixture.tres")
	var passed := true

	var absolute_test_root := ProjectSettings.globalize_path(test_root)
	var absolute_imported_root := ProjectSettings.globalize_path(imported_root)
	if DirAccess.dir_exists_absolute(absolute_test_root) or FileAccess.file_exists(absolute_test_root) \
		or DirAccess.dir_exists_absolute(absolute_imported_root) or FileAccess.file_exists(absolute_imported_root):
		push_error("SongData zip test path already exists; refusing to overwrite it.")
		return

	if DirAccess.make_dir_recursive_absolute(absolute_test_root) != OK:
		push_error("Could not create SongData zip test directory.")
		return

	var midi_path := test_root.path_join("fixture.mid")
	var click_path := test_root.path_join("click.wav")
	var stem_path := test_root.path_join("stem.wav")
	passed = _write_test_file(midi_path, PackedByteArray([77, 84, 104, 100])) and passed
	passed = _write_test_file(click_path, PackedByteArray([82, 73, 70, 70])) and passed
	passed = _write_test_file(stem_path, PackedByteArray([87, 65, 86, 69])) and passed

	var song := SongData.new()
	song.title = "Zip Round Trip Fixture"
	song.midi_file = midi_path
	song.click_track = click_path
	var track := SongTrackData.new()
	track.midi_track_name = "Test Track"
	track.audio_file = stem_path
	song.tracks.append(track)

	var save_error := ResourceSaver.save(song, fixture_path)
	passed = _expect(save_error == OK, "Could not save fixture SongData resource.") and passed
	if save_error == OK:
		var saved_song := ResourceLoader.load(fixture_path, "SongData") as SongData
		passed = _expect(saved_song != null, "Could not reload fixture SongData resource.") and passed
		if saved_song:
			var zip_error := saved_song.make_zip(zip_path)
			passed = _expect(zip_error == OK, "SongData.make_zip() failed with error %d." % zip_error) and passed
			if zip_error == OK:
				passed = _check_archive(zip_path) and passed
				var import_error := SongData.import_zip(zip_path)
				passed = _expect(import_error == OK, "SongData.import_zip() failed with error %d." % import_error) and passed
				if import_error == OK:
					passed = _check_imported_song(imported_root) and passed

	_remove_tree(imported_root)
	_remove_tree(test_root)
	if passed:
		print("SongData zip round-trip test passed.")
	else:
		push_error("SongData zip round-trip test failed.")

func _write_test_file(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return _expect(false, "Could not create test payload: %s" % path)
	file.store_buffer(bytes)
	file.close()
	return true

func _check_archive(path: String) -> bool:
	var reader := ZIPReader.new()
	var open_error := reader.open(path)
	if not _expect(open_error == OK, "Could not open generated zip archive."):
		return false

	var required_files := ["fixture.mid", "click.wav", "stem.wav", "fixture.tres"]
	var archive_files := reader.get_files()
	var passed := true
	for file_name in required_files:
		passed = _expect(archive_files.has(file_name), "Archive is missing %s." % file_name) and passed
		if file_name != "fixture.tres" and archive_files.has(file_name):
			passed = _expect(reader.read_file(file_name) == _expected_payload(file_name), "Archive payload differs for %s." % file_name) and passed
	reader.close()
	return passed

func _check_imported_song(imported_root: String) -> bool:
	var resource_path := imported_root.path_join("fixture.tres")
	var song := ResourceLoader.load(resource_path, "SongData") as SongData
	if not _expect(song != null, "Could not load imported SongData resource."):
		return false

	var passed := true
	passed = _expect(song.title == "Zip Round Trip Fixture", "Imported song title did not round-trip.") and passed
	passed = _expect(song.midi_file == "fixture.mid", "Imported MIDI path did not round-trip.") and passed
	passed = _expect(song.click_track == "click.wav", "Imported click track path did not round-trip.") and passed
	passed = _expect(song.tracks.size() == 1, "Imported track list did not round-trip.") and passed
	if song.tracks.size() == 1:
		passed = _expect(song.tracks[0].audio_file == "stem.wav", "Imported stem path did not round-trip.") and passed
	for file_name in ["fixture.mid", "click.wav", "stem.wav"]:
		var imported_path := imported_root.path_join(file_name)
		passed = _expect(FileAccess.file_exists(imported_path), "Imported file is missing: %s" % file_name) and passed
		if FileAccess.file_exists(imported_path):
			passed = _expect(_read_file(imported_path) == _expected_payload(file_name), "Imported payload differs for %s." % file_name) and passed
	return passed

func _expected_payload(file_name: String) -> PackedByteArray:
	match file_name:
		"fixture.mid":
			return PackedByteArray([77, 84, 104, 100])
		"click.wav":
			return PackedByteArray([82, 73, 70, 70])
		"stem.wav":
			return PackedByteArray([87, 65, 86, 69])
	return PackedByteArray()

func _read_file(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return PackedByteArray()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes

func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
	return condition

func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if entry != "." and entry != "..":
				var child_path := path.path_join(entry)
				if dir.current_is_dir():
					_remove_tree(child_path)
				else:
					DirAccess.remove_absolute(ProjectSettings.globalize_path(child_path))
			entry = dir.get_next()
		dir.list_dir_end()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
