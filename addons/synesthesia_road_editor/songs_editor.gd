@tool

extends HSplitContainer

enum AudioFileType {
	CLICK_TRACK,
	PREVIEW_AUDIO,
	DECIDE_AUDIO
}

const SONGS_PATH: String = "user://song"

var songs: Dictionary = {}
var current_folder: String = ""
var current_song: SongData = null
var current_moggsong_path: String = ""
var dirty: bool = false
var undo_redo := EditorInterface.get_editor_undo_redo()
var audio_file_dialog_dest: AudioFileType = AudioFileType.CLICK_TRACK
var _next_folder: String = ""

var checkpoint_spins: Array[SpinBox] = []

func _ready() -> void:
	_refresh_song_list()
	_rebuild_song_list_ui()
	%SwitchConfirmDialog.add_button("Discard", true, "discard")

func _refresh_song_list() -> void:
	var dir = DirAccess.open(SONGS_PATH)
	if not dir:
		push_error("Failed to open songs directory: %s" % SONGS_PATH)
		return
	var folders = dir.get_directories()
	for folder in folders:
		var song_file_path = _get_song_data_path(folder)
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
	current_song.changed.disconnect(_on_current_song_changed)
	undo_redo.clear_history(undo_redo.get_object_history_id(current_song))
	current_song = song_res
	current_folder = folder
	current_song.changed.connect(_on_current_song_changed)
	current_moggsong_path = _get_moggsong_path(folder) if FileAccess.file_exists(_get_moggsong_path(folder)) else ""
	for fd: EditorFileDialog in [%AudioFileDialog, %AlbumArtFileDialog, %MidiFileDialog, %MoggSongFileDialog]:
		fd.root_subfolder = _get_song_folder_path(folder)
		fd.current_dir = _get_song_folder_path(folder)
	var rich_name = "%s - %s" % [current_song.artist, current_song.long_title]
	songs[folder]["rich_name"] = rich_name
	%SongList.set_item_text(songs[folder].list_index, rich_name)
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
	%BpmOverrideCheck.button_pressed = current_song.bpm_fix
	%BpmSpin.value = current_song.fixed_bpm
	%LeadInSpin.value = current_song.lead_in_measures
	%PlayableSpin.value = current_song.playable_measures
	%CheckpointCountSpin.value = current_song.checkpoints.size()
	_load_checkpoint_values()
	_load_track_groups()

func _resize_track_groups(count: int):
	%NoTracksLabel.visible = (count == 0)
	var delta = count - %TracksContainer.get_child_count()
	if delta > 0:
		for i in range(delta):
			var new_group = preload("res://addons/synesthesia_road_editor/track_group.tscn").instantiate()
			new_group.idx = %TracksContainer.get_child_count()
			new_group.remove_requested.connect(_on_track_group_remove_requested)
			%TracksContainer.add_child(new_group)
	elif delta < 0:
		for i in range(abs(delta)):
			var rem_group = %TracksContainer.get_child(%TracksContainer.get_child_count() - 1)
			%TracksContainer.remove_child(rem_group)
			rem_group.queue_free()

func _load_track_groups():
	_resize_track_groups(current_song.tracks.size())
	for i in range(current_song.tracks.size()):
		var track_data = current_song.tracks[i]
		var track_group = %TracksContainer.get_child(i)
		track_group.set_track_data(track_data)

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
	
func _rescan_midi_track_names():
	var new_track_names = current_song.track_names
	for i in %TracksContainer.get_child_count():
		var track_group = %TracksContainer.get_child(i)
		track_group.update_midi_track_names(new_track_names)

func _set_dirty(value: bool) -> void:
	dirty = value
	%SaveButton.disabled = not dirty
	%RevertButton.disabled = not dirty

func _get_song_folder_path(folder: String) -> String:
	return SONGS_PATH.path_join(folder)

func _get_song_data_path(folder: String) -> String:
	return _get_song_folder_path(folder).path_join("%s.tres" % folder)

func _get_moggsong_path(folder: String) -> String:
	return _get_song_folder_path(folder).path_join("%s.moggsong" % folder)

func _on_current_song_changed():
	pass

#region Signal Handling
func _on_song_filter_field_text_changed() -> void:
	_rebuild_song_list_ui(%SongFilter.text)

func _on_rescan_button_pressed() -> void:
	_refresh_song_list()
	_rebuild_song_list_ui(%SongFilter.text)

func _on_song_list_item_selected(index: int) -> void:
	var folder = %SongList.get_item_metadata(index)
	if folder != current_folder:
		if dirty:
			_next_folder = folder
			%SwitchConfirmDialog.popup_centered()
		else:
			_load_song(folder)
			_update_editor_fields()


func _on_new_song_button_pressed() -> void:
	%NewSongPopup.popup_centered()


func _on_import_moggsong_button_pressed() -> void:
	%MoggSongFileDialog.popup_centered()


func _on_save_button_pressed() -> void:
	var path = _get_song_data_path(current_folder)
	ResourceSaver.save(current_song, path)
	_set_dirty(false)


func _on_revert_button_pressed() -> void:
	var old_data = current_song.duplicate_deep()
	var new_data = ResourceLoader.load(current_song.resource_path)
	undo_redo.create_action("Revert Song Data", UndoRedo.MERGE_DISABLE, current_song)
	undo_redo.add_do_property(self, "current_song", new_data)
	undo_redo.add_do_method(self, "_set_dirty", false)
	undo_redo.add_undo_property(self, "current_song", old_data)
	undo_redo.add_undo_method(self, "_set_dirty", dirty)
	undo_redo.commit_action()


func _on_title_field_text_changed() -> void:
	var old_title = current_song.title
	undo_redo.create_action("Change Song Title")
	undo_redo.add_do_property(current_song, "title", %TitleField.text)
	undo_redo.add_do_property(%TitleField, "text", %TitleField.text)
	undo_redo.add_do_method(self, "_set_dirty", true)
	undo_redo.add_undo_property(current_song, "title", old_title)
	undo_redo.add_undo_property(%TitleField, "text", old_title)
	undo_redo.add_undo_method(self, "_set_dirty", dirty)
	undo_redo.commit_action()


func _on_subtitle_field_text_changed() -> void:
	var old_subtitle = current_song.subtitle
	undo_redo.create_action("Change Subtitle")
	undo_redo.add_do_property(current_song, "subtitle", %SubtitleField.text)
	undo_redo.add_do_property(%SubtitleField, "text", %SubtitleField.text)
	undo_redo.add_do_method(self, "_set_dirty", true)
	undo_redo.add_undo_property(current_song, "subtitle", old_subtitle)
	undo_redo.add_undo_property(%SubtitleField, "text", old_subtitle)
	undo_redo.add_undo_method(self, "_set_dirty", dirty)
	undo_redo.commit_action()


func _on_artist_field_text_changed() -> void:
	var old_artist = current_song.artist
	undo_redo.create_action("Change Artist")
	undo_redo.add_do_property(current_song, "artist", %ArtistField.text)
	undo_redo.add_do_property(%ArtistField, "text", %ArtistField.text)
	undo_redo.add_do_method(self, "_set_dirty", true)
	undo_redo.add_undo_property(current_song, "artist", old_artist)
	undo_redo.add_undo_property(%ArtistField, "text", old_artist)
	undo_redo.add_undo_method(self, "_set_dirty", dirty)
	undo_redo.commit_action()


func _on_genre_field_text_changed() -> void:
	var old_genre = current_song.genre
	undo_redo.create_action("Change Genre")
	undo_redo.add_do_property(current_song, "genre", %GenreField.text)
	undo_redo.add_do_property(%GenreField, "text", %GenreField.text)
	undo_redo.add_do_method(self, "_set_dirty", true)
	undo_redo.add_undo_property(current_song, "genre", old_genre)
	undo_redo.add_undo_property(%GenreField, "text", old_genre)
	undo_redo.add_undo_method(self, "_set_dirty", dirty)
	undo_redo.commit_action()


func _on_source_field_text_changed() -> void:
	var old_source = current_song.source
	undo_redo.create_action("Change Source")
	undo_redo.add_do_property(current_song, "source", %SourceField.text)
	undo_redo.add_do_property(%SourceField, "text", %SourceField.text)
	undo_redo.add_do_method(self, "_set_dirty", true)
	undo_redo.add_undo_property(current_song, "source", old_source)
	undo_redo.add_undo_property(%SourceField, "text", old_source)
	undo_redo.add_undo_method(self, "_set_dirty", dirty)
	undo_redo.commit_action()


func _on_description_field_text_changed() -> void:
	var old_description = current_song.description
	undo_redo.create_action("Change Description")
	undo_redo.add_do_property(current_song, "description", %DescriptionField.text)
	undo_redo.add_do_property(%DescriptionField, "text", %DescriptionField.text)
	undo_redo.add_do_method(self, "_set_dirty", true)
	undo_redo.add_undo_property(current_song, "description", old_description)
	undo_redo.add_undo_property(%DescriptionField, "text", old_description)
	undo_redo.add_undo_method(self, "_set_dirty", dirty)
	undo_redo.commit_action()


func _on_cover_art_browse_button_pressed() -> void:
	%AlbumArtFileDialog.popup_centered()


func _on_cover_art_reset_button_pressed() -> void:
	var old_texture = current_song.cover_art
	undo_redo.create_action("Clear Cover Art")
	undo_redo.add_do_property(current_song, "cover_art", null)
	undo_redo.add_do_property(%CoverArt, "visible", false)
	undo_redo.add_do_property(%DefaultPlaceholder, "visible", true)
	undo_redo.add_do_property(%CoverArtResetButton, "disabled", true)
	undo_redo.add_undo_property(current_song, "cover_art", old_texture)
	undo_redo.add_undo_property(%CoverArt, "visible", true)
	undo_redo.add_undo_property(%DefaultPlaceholder, "visible", false)
	undo_redo.add_undo_property(%CoverArtResetButton, "disabled", false)
	undo_redo.commit_action()



func _on_midi_file_browse_button_pressed() -> void:
	%MidiFileDialog.popup_centered()


func _on_click_track_browse_button_pressed() -> void:
	audio_file_dialog_dest = AudioFileType.CLICK_TRACK
	%AudioFileDialog.popup_centered()


func _on_preview_audio_browse_button_pressed() -> void:
	audio_file_dialog_dest = AudioFileType.PREVIEW_AUDIO
	%AudioFileDialog.popup_centered()


func _on_decide_audio_browse_button_pressed() -> void:
	audio_file_dialog_dest = AudioFileType.DECIDE_AUDIO
	%AudioFileDialog.popup_centered()


func _on_preview_audio_clear_button_pressed() -> void:
	pass # Replace with function body.


func _on_decide_audio_clear_button_pressed() -> void:
	pass # Replace with function body.


func _on_rescan_midi_button_pressed() -> void:
	# This is for if the MIDI file path is the same but the data changed
	# (i.e. the user replaced the file with a new version). We need to reload the MIDI data and update the track names in the editor.
	current_song._load_midi_data()
	_rescan_midi_track_names()


func _on_add_track_button_pressed() -> void:
	var old_array = current_song.tracks.duplicate()
	var new_array = current_song.tracks.duplicate()
	new_array.append(SongTrackData.new())
	undo_redo.create_action("Add Track")
	undo_redo.add_do_property(current_song, "tracks", new_array)
	undo_redo.add_do_method(self, "_resize_track_groups")
	undo_redo.add_do_method(self, "_set_dirty", true)
	undo_redo.add_undo_property(current_song, "tracks", old_array)
	undo_redo.add_undo_method(self, "_resize_track_groups")
	undo_redo.add_undo_method(self, "_set_dirty", dirty)
	undo_redo.commit_action()

func _on_track_group_remove_requested(idx: int):
	var old_array = current_song.tracks.duplicate()
	var new_array = current_song.tracks.duplicate()
	new_array.remove_at(idx)
	undo_redo.create_action("Remove Track")
	undo_redo.add_do_property(current_song, "tracks", new_array)
	undo_redo.add_do_method(self, "_load_track_groups")
	undo_redo.add_do_method(self, "_set_dirty", true)
	undo_redo.add_undo_property(current_song, "tracks", old_array)
	undo_redo.add_undo_method(self, "_load_track_groups")
	undo_redo.add_undo_method(self, "_set_dirty", dirty)
	undo_redo.commit_action()

func _on_extract_audio_button_pressed() -> void:
	%ExtractConfirmDialog.popup_centered()


func _on_bpm_override_check_toggled(toggled_on: bool) -> void:
	var old_bpm_fix = current_song.bpm_fix
	undo_redo.create_action("Toggle BPM Override")
	undo_redo.add_do_property(current_song, "bpm_fix", toggled_on)
	undo_redo.add_do_property(%BpmSpin, "editable", toggled_on)
	undo_redo.add_do_method(self, "_set_dirty", true)
	undo_redo.add_undo_property(current_song, "bpm_fix", old_bpm_fix)
	undo_redo.add_undo_property(%BpmSpin, "editable", old_bpm_fix)
	undo_redo.add_undo_property(self, "_set_dirty", dirty)
	undo_redo.commit_action()


func _on_bpm_spin_changed() -> void:
	var old_bpm = current_song.fixed_bpm
	undo_redo.create_action("Change BPM")
	undo_redo.add_do_property(current_song, "fixed_bpm", %BpmSpin.value)
	undo_redo.add_do_method(%BpmSpin, "set_value_no_signal", %BpmSpin.value)
	undo_redo.add_do_method(self, "_set_dirty", true)
	undo_redo.add_undo_property(current_song, "fixed_bpm", old_bpm)
	undo_redo.add_undo_method(%BpmSpin, "set_value_no_signal", old_bpm)
	undo_redo.commit_action()


func _on_lead_in_spin_changed() -> void:
	var old_lead_in = current_song.lead_in_measures
	undo_redo.create_action("Change Lead-In Measures")
	undo_redo.add_do_property(current_song, "lead_in_measures", %LeadInSpin.value)
	undo_redo.add_do_method(%LeadInSpin, "set_value_no_signal", %LeadInSpin.value)
	undo_redo.add_undo_property(current_song, "lead_in_measures", old_lead_in)
	undo_redo.add_undo_method(%LeadInSpin, "set_value_no_signal", old_lead_in)
	undo_redo.commit_action()


func _on_playable_spin_changed() -> void:
	var old_playable = current_song.playable_measures
	undo_redo.create_action("Change Playable Measures")
	undo_redo.add_do_property(current_song, "playable_measures", %PlayableSpin.value)
	undo_redo.add_do_method(%PlayableSpin, "set_value_no_signal", %PlayableSpin.value)
	undo_redo.add_do_method(self, "_set_dirty", true)
	undo_redo.add_undo_property(current_song, "playable_measures", old_playable)
	undo_redo.add_undo_method(%PlayableSpin, "set_value_no_signal", old_playable)
	undo_redo.commit_action()


func _on_checkpoint_count_spin_changed() -> void:
	var old_checkpoints = current_song.checkpoints.duplicate()

	var new_checkpoint_count = int(%CheckpointCountSpin.value)
	var new_checkpoints = current_song.checkpoints.duplicate()
	new_checkpoints.resize(new_checkpoint_count)

	undo_redo.create_action("Change Checkpoint Count")
	undo_redo.add_do_property(current_song, "checkpoints", new_checkpoints)
	undo_redo.add_do_method(%CheckpointCountSpin, "set_value_no_signal", new_checkpoint_count)
	undo_redo.add_do_method(self, "_load_checkpoint_values")
	undo_redo.add_do_method(self, "_set_dirty", true)
	undo_redo.add_undo_property(current_song, "checkpoints", old_checkpoints)
	undo_redo.add_undo_method(%CheckpointCountSpin, "set_value_no_signal", old_checkpoints.size())
	undo_redo.add_undo_method(self, "_load_checkpoint_values")
	undo_redo.commit_action()


func _on_audio_file_dialog_file_selected(path: String) -> void:
	pass # Replace with function body.


func _on_switch_confirm_dialog_confirmed() -> void:
	ResourceSaver.save(current_song)


func _on_switch_confirm_dialog_canceled() -> void:
	%SongList.select(songs[current_folder].list_index)
	_next_folder = ""


func _on_switch_confirm_dialog_custom_action(action: StringName) -> void:
	if action == "discard":
		var next_idx = songs[_next_folder].list_index
		_load_song(%SongList.get_item_metadata(next_idx))
		_update_editor_fields()
		_next_folder = ""


func _on_new_song_popup_confirmed() -> void:
	pass # Replace with function body.


func _on_extract_confirm_dialog_confirmed() -> void:
	pass # Replace with function body.


func _on_midi_file_dialog_file_selected(path: String) -> void:
	pass # Replace with function body.


func _on_mogg_song_file_dialog_file_selected(path: String) -> void:
	var old_song_data = current_song.duplicate_deep()
	var new_song_data = MoggsongParser.create_songdata_from_moggsong(path)


func _on_album_art_file_dialog_file_selected(path: String) -> void:
	pass # Replace with function body.


#endregion
