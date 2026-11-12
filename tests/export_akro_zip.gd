@tool
extends EditorScript

const SONG_DATA_PATH := "res://song/akro/akro.tres"
const ZIP_PATH := "res://song/akro.zip"

func _run() -> void:
	var song_data := ResourceLoader.load(SONG_DATA_PATH) as SongData
	if song_data == null:
		push_error("Could not load SongData resource: %s" % SONG_DATA_PATH)
		return

	var err := song_data.make_zip(ZIP_PATH)
	if err != OK:
		push_error("Could not create Akro zip: %s" % err)
		return

	print("Created Akro zip: %s" % ZIP_PATH)
