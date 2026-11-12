extends Control

const PAK_QUERY = """SELECT "folder_id", "pak_name", "title"
FROM "v_song_select"
ORDER BY "pak_sort" COLLATE NOCASE ASC, "sort_key" COLLATE NOCASE ASC;"""
const CATALOG_MENU = 0

var root

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	await get_tree().process_frame
	Transition.play_menu_track(Transition.MenuTracks.STATS, 1)
	_rebuild_song_tree()
	await Transition.audio_transition_completed
	Transition.start_transition_out()
	await Transition.animation_completed


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _rebuild_song_tree() -> void:
	var db = SessionManager.library_db
	var tree: Tree = %SongTree

	var success = db.query(PAK_QUERY)
	if not success:
		return
	var pak_name := ""
	var branch: TreeItem
	root = tree.create_item()
	for row in db.query_result:
		if row["pak_name"] != pak_name:
			pak_name = row["pak_name"]
			branch = tree.create_item(root)
			branch.set_text(0, pak_name)
		var song_item = tree.create_item(branch)
		song_item.set_text(0, row["title"])
		song_item.set_metadata(0, row["folder_id"])



func _on_catalog_menu_id_pressed(id: int) -> void:
	match id:
		0, 1:
			if id == 1:
				%SongTree.clear()
				SessionManager.close_library_db()
				DirAccess.remove_absolute(SessionManager.LIBRARY_DB_PATH)
			await SongCatalog.scan_for_songs(not SessionManager.library_db_file_exists)
			SessionManager.previous_select_options.clear()
			_rebuild_song_tree()
			SongCatalog.make_menu_structure()

func _on_back_button_pressed() -> void:
	Transition.start_transition_in()
	await Transition.animation_completed
	get_tree().change_scene_to_file("res://menu/song_select.tscn")
