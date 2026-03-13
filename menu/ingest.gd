extends TextureRect

var song_root_directory

func _ready() -> void:
	await get_tree().process_frame # Wait a frame for UI to initialize
	%ProgressBar.max_value = DirAccess.get_directories_at(SongCatalog.SONG_DIRECTORY_PATH).size()
	var library_file_exists = FileAccess.file_exists(SessionManager.LIBRARY_DB_PATH)
	if not library_file_exists:
		%Label.text = "Initializing library file for the first time..."
	await get_tree().process_frame
	SongCatalog.scan_for_songs(!library_file_exists)
	SongCatalog.make_menu_structure()

	get_tree().change_scene_to_file("res://menu/SongSelect.tscn")
