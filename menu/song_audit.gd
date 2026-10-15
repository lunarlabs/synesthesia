extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	await get_tree().process_frame
	Transition.play_menu_track(Transition.MenuTracks.STATS, 1)
	await Transition.audio_transition_completed
	Transition.start_transition_out()
	await Transition.animation_completed


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_catalog_menu_id_pressed(id: int) -> void:
	print(id)
	match id:
		0, 1:
			if id == 1:
				SessionManager.close_library_db()
				DirAccess.remove_absolute(SessionManager.LIBRARY_DB_PATH)
			await SongCatalog.scan_for_songs(SessionManager.library_db_file_exists)
			SongCatalog.make_menu_structure()
		3:
			Transition.start_transition_in()
			await Transition.animation_completed
			get_tree().change_scene_to_file("res://menu/song_select.tscn")
