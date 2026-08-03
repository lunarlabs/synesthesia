@tool
extends EditorScript

func _run() -> void:
	var source_dir := "res://song"
	var dest_dir := "user://song"


	if not DirAccess.dir_exists_absolute(dest_dir):
		var err := DirAccess.make_dir_absolute(dest_dir)
		if err != OK:
			push_error("Failed to create base destination directory.")
			return

	var dir := DirAccess.open(source_dir)
	if not dir:
		push_error("Source directory doesn't exist.")
		return

	var subdir_list := dir.get_directories()
	for subdir in subdir_list:
		var abs_source_path := dir.get_current_dir().path_join(subdir)
		var abs_dest_path := dest_dir.path_join(subdir)
		print(abs_source_path + " -> " + abs_dest_path + "...")

		if not DirAccess.dir_exists_absolute(abs_dest_path):
			var err = DirAccess.make_dir_absolute(abs_dest_path)
			if err != OK and err != ERR_ALREADY_EXISTS:
				push_error("Failed to create directory: " + abs_dest_path)
				continue # Skip this folder, but continue with the rest

		var files := DirAccess.get_files_at(abs_source_path)

		# COMPLETION: Actually copy the files
		for filename in files:
			var source_file := abs_source_path.path_join(filename)
			var dest_file := abs_dest_path.path_join(filename)
			if filename.get_extension() == "tres":
				var sd = ResourceLoader.load(source_file,
					"SongData", ResourceLoader.CACHE_MODE_IGNORE) as SongData

				if not sd:
					push_error("Failed to load or cast SongData: " + source_file)
					continue

				var missing_required_file := false
				for reqd_file in [sd.midi_file, sd.click_track]:
					if not FileAccess.file_exists(reqd_file):
						missing_required_file = true
						break

				if missing_required_file:
					continue

				sd.midi_file = abs_dest_path.path_join(sd.midi_file.get_file())
				sd.click_track = abs_dest_path.path_join(sd.click_track.get_file())

				missing_required_file = false
				for track in sd.tracks:
					if not FileAccess.file_exists(track.audio_file):
						missing_required_file = true
						break
					track.audio_file = abs_dest_path.path_join(track.audio_file.get_file())

				if missing_required_file:
					continue

				if FileAccess.file_exists(sd.preview_audio):
					sd.preview_audio = abs_dest_path.path_join(sd.preview_audio.get_file())
				sd.selection_audio = "" # We didn't use any customs yet anyway and nothing loads it yet

				ResourceSaver.save(sd, dest_file)
				print ("saved SongData")
			elif filename.get_extension() != "import":
				var copy_err = DirAccess.copy_absolute(source_file, dest_file)
				if copy_err != OK:
					push_error("failed to copy " + source_file)
				print(filename)
