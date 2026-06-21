extends TextureRect

var song_root_directory

func _ready() -> void:
	await get_tree().process_frame # Wait a frame for UI to initialize
	%ProgressBar.max_value = DirAccess.get_directories_at(SongCatalog.SONG_DIRECTORY_PATH).size()
	var library_file_exists = SessionManager.library_db_file_exists
	if not library_file_exists:
		%Label.text = "Initializing library file for the first time..."
	await get_tree().process_frame
	await SongCatalog.scan_for_songs(!library_file_exists)
	SongCatalog.make_menu_structure()
	await get_tree().create_timer(1.0).timeout
	SessionManager.read_modifiers()
	Transition.start_transition_in()
	await Transition.animation_completed
	get_tree().change_scene_to_file("res://menu/song_select.tscn")
