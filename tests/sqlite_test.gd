extends Node

const SONG_DIRECTORY_PATH = "res://song/"

func _ready():
	var dir = DirAccess.open(SONG_DIRECTORY_PATH)
	if not dir:
		push_error("Failed to open song directory.")
		return

	dir.list_dir_begin()
	var folder_name = dir.get_next()
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			print("Found song folder: %s" % folder_name)
			SongCatalog.process_song(folder_name)
		folder_name = dir.get_next()
	dir.list_dir_end()
