@tool
extends EditorScript

const SCAN_ROOT := "res://song"
var thread: Thread

static var is_running := false

func _run():
	if is_running:
		printerr("Script already running.")
		return
	is_running = true
	var moggsongs: Array[String] = []
	var dir = DirAccess.open(SCAN_ROOT)

	if not dir:
		push_error("Can't open directory.")
		is_running = false
		return

	# Godot 4 allows direct iteration over directories, avoiding the while loop entirely
	for folder_name in dir.get_directories():

		# Skip hidden folders
		if folder_name.begins_with("."):
			continue

		var file_path = "res://song/%s/%s.tres" % [folder_name, folder_name]

		# Check if the .tres file exists BEFORE attempting to load it
		if not FileAccess.file_exists(file_path):
			continue

		var song_data = ResourceLoader.load(file_path) as SongData

		# Ensure the resource loaded properly before accessing its properties
		if not song_data:
			push_error("Failed to load SongData resource at: %s" % file_path)
			continue

		var needs_refreshing = false

		# 1. Check the click track
		if not FileAccess.file_exists(ResourceUID.ensure_path(song_data.click_track)):
			needs_refreshing = true

		# 2. Check the individual tracks (only if we don't already need refreshing)
		if not needs_refreshing:
			for track in song_data.tracks:
				var track_data = track as SongTrackData
				if not track_data or not FileAccess.file_exists(ResourceUID.ensure_path(track_data.audio_file)):
					needs_refreshing = true
					break # Exit the track loop early since we already know it needs a refresh

		# Append with proper string formatting
		if needs_refreshing:
			moggsongs.append("res://song/%s/%s.moggsong" % [folder_name, folder_name])
	if not moggsongs.is_empty():
		thread = Thread.new()
		thread.start(Callable(self, "_thread_func").bind(moggsongs))
		while thread.is_alive():
			await Engine.get_main_loop().process_frame
		thread.wait_to_finish()
	is_running = false

func _thread_func(moggsongs: Array[String]):
	for file in moggsongs:
		MoggsongParser.update_songdata_tracks(file)
