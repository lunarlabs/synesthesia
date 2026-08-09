@tool

extends HSplitContainer

const SONGS_PATH: String = "user://songs"

var songs: Dictionary = {}
var current_folder: String = ""
var current_song: SongData = null
var dirty: bool = false

var checkpoint_spins: Array[SpinBox] = []

func _refresh_song_list() -> void:
	var dir = DirAccess.open(SONGS_PATH)
	if not dir:
		push_error("Failed to open songs directory: %s" % SONGS_PATH)
		return
	var folders = dir.get_directories()
	for folder in folders:
		var song_file_path = SONGS_PATH.path_join(folder).path_join("%s.tres" % folder)
		if FileAccess.file_exists(song_file_path) and not songs.has(folder):
			songs[folder] = {"folder": folder,
				"path": song_file_path,}

func _rebuild_song_list_ui(filter: String = "") -> void:
	%SongList.clear()
	var keys: Array = songs.keys()
	keys.sort_custom(func(a, b): return a.to_lower().naturalnocasecmp_to(b.to_lower()) > 0)
	for entry in keys:
		if filter == "" or entry.to_lower().findn(filter.to_lower()) != -1:
			var item = %SongList.add_item(songs[entry].get("rich_name", entry))
			%SongList.set_item_metadata(item, entry)
			songs[entry]["list_index"] = item
			if current_folder == entry:
				%SongList.select(item)
		else:
			songs[entry]["list_index"] = -1

func _load_song(folder: String) -> void:
	if not songs.has(folder):
		push_error("Song folder not found: %s" % folder)
		return
	var song_path = songs[folder].path
	var song_res = ResourceLoader.load(song_path)
	if not song_res:
		push_error("Failed to load song resource from %s" % song_path)
		return
	if not song_res is SongData:
		push_error("Resource at %s is not a SongData resource." % song_path)
		return
	current_song = song_res
	current_folder = folder
	_set_dirty(false)

func _save_current_song() -> void:
	if not current_song or current_folder == "":
		push_error("No song is currently loaded to save.")
		return
	var song_path = songs[current_folder].path
	var err = ResourceSaver.save(current_song, song_path)
	if err != OK:
		push_error("Failed to save song resource to %s. Error code: %d" % [song_path, err])
		return
	_set_dirty(false)

func _revert_current_song() -> void:
	if not current_song or current_folder == "":
		push_error("No song is currently loaded to revert.")
		return
	_load_song(current_folder)

func _update_editor_fields() -> void:
	if not current_song:
		push_error("No song is currently loaded to update editor fields.")
		%SongEditorContainer.visible = false
		%NoSongSelectedContainer.visible = true
		return
	%SongEditorContainer.visible = true
	%NoSongSelectedContainer.visible = false
	%TitleField.text = current_song.title
	%SubtitleField.text = current_song.sub_title
	%ArtistField.text = current_song.artist
	%GenreField.text = current_song.genre
	%SourceField.text = current_song.source
	%DescriptionField.text = current_song.description
	if current_song.cover_art:
		%CoverArt.texture = current_song.cover_art
		%CoverArt.show()
		%DefaultPlaceholder.hide()
		%CoverArtResetButton.disabled = false
	else:
		%CoverArt.hide()
		%DefaultPlaceholder.show()
		%CoverArtResetButton.disabled = true
	%MidiFileField.text = current_song.midi_file
	%ClickTrackField.text = current_song.click_track
	%PreviewAudioField.text = current_song.preview_audio
	%PreviewAudioClearButton.disabled = current_song.preview_audio.is_empty()
	%DecideAudioField.text = current_song.selection_audio
	%DecideAudioClearButton.disabled = current_song.selection_audio.is_empty()

func _resize_checkpoint_spins(count: int):
	var delta = count - checkpoint_spins.size() 
	if delta > 0:
		for i in range(delta):
			var new_spin = SpinBox.new()
			checkpoint_spins.append(new_spin)
			new_spin.max_value = 500
			%CheckpointContainer.add_child(new_spin)
	elif delta < 0:
		for i in range(abs(delta)):
			var rem_spin = checkpoint_spins.pop_back()
			rem_spin.get_parent().remove_child(rem_spin)
			rem_spin.queue_free()

func _load_checkpoint_values():
	_resize_checkpoint_spins(current_song.checkpoints.size())
	for i in current_song.checkpoints.size():
		checkpoint_spins[i].value = current_song.checkpoints[i]
	
	

func _set_dirty(value: bool) -> void:
	dirty = value
	%SaveButton.disabled = not dirty
	%RevertButton.disabled = not dirty

#region Signal Handling
func _on_song_filter_field_text_changed() -> void:
	_rebuild_song_list_ui(%SongFilter.text)

func _on_rescan_button_pressed() -> void:
	_refresh_song_list()
	_rebuild_song_list_ui(%SongFilter.text)


func _on_song_list_item_selected(index: int) -> void:
	var folder = %SongList.get_item_metadata(index)
	var _save_and_switch = func():
		_save_current_song()
		_load_song(folder)
		_update_editor_fields()
	var _discard_and_switch = func():
		_load_song(folder)
		_update_editor_fields()
	var _cancel_switch = func():
		%SongList.select(songs[current_folder].list_index)
	if folder != current_folder:
		if dirty:
			var confirm = ConfirmationDialog.new()
			confirm.dialog_text = "You have unsaved changes. Do you want to save before switching songs?"
			confirm.ok_button_text = "Save"
			confirm.add_button("Discard", true, "discard")
			confirm.connect("confirmed", _save_and_switch)
			confirm.connect("canceled", _cancel_switch)
			confirm.connect("custom_action", _discard_and_switch)
			confirm.popup_centered()
		else:
			_load_song(folder)
			_update_editor_fields()


func _on_new_song_button_pressed() -> void:
	pass # Replace with function body.


func _on_import_moggsong_button_pressed() -> void:
	pass # Replace with function body.


func _on_save_button_pressed() -> void:
	pass # Replace with function body.


func _on_revert_button_pressed() -> void:
	pass # Replace with function body.


func _on_title_field_text_changed() -> void:
	pass # Replace with function body.


func _on_subtitle_field_text_changed() -> void:
	pass # Replace with function body.


func _on_artist_field_text_changed() -> void:
	pass # Replace with function body.


func _on_genre_field_text_changed() -> void:
	pass # Replace with function body.


func _on_source_field_text_changed() -> void:
	pass # Replace with function body.


func _on_description_field_text_changed() -> void:
	pass # Replace with function body.


func _on_cover_art_browse_button_pressed() -> void:
	pass # Replace with function body.


func _on_cover_art_reset_button_pressed() -> void:
	pass # Replace with function body.


func _on_midi_file_browse_button_pressed() -> void:
	pass # Replace with function body.


func _on_click_track_browse_button_pressed() -> void:
	pass # Replace with function body.


func _on_preview_audio_browse_button_pressed() -> void:
	pass # Replace with function body.


func _on_decide_audio_browse_button_pressed() -> void:
	pass # Replace with function body.


func _on_preview_audio_clear_button_pressed() -> void:
	pass # Replace with function body.


func _on_decide_audio_clear_button_pressed() -> void:
	pass # Replace with function body.


func _on_rescan_midi_button_pressed() -> void:
	pass # Replace with function body.


func _on_add_track_button_pressed() -> void:
	pass # Replace with function body.


func _on_extract_audio_button_pressed() -> void:
	pass # Replace with function body.


func _on_bpm_override_check_toggled(toggled_on: bool) -> void:
	pass # Replace with function body.


func _on_bpm_spin_changed() -> void:
	pass # Replace with function body.


func _on_lead_in_spin_changed() -> void:
	pass # Replace with function body.


func _on_playable_spin_changed() -> void:
	pass # Replace with function body.


func _on_checkpoint_count_spin_changed() -> void:
	pass # Replace with function body.

#endregion
