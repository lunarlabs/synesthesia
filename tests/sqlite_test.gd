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
	_test_queries()

func _test_queries():
	var success = SessionManager.library_db.query("""SELECT 
	folder_id, 
	title, 
	sub_title, 
	artist, 
	genre, 
	bpm, 
	available_difficulties, 
	source_name, 
	files_ok, 
	resource_hash,
	midi_hash
	FROM v_song_select;""")
	var result = SessionManager.library_db.query_result
	print(success)
	print(result)
