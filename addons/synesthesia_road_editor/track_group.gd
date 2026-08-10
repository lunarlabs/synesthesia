@tool
extends HBoxContainer

var idx: int
var _track_data: SongTrackData
var _cached_track_names: Array[String]
var undo_redo := EditorInterface.get_editor_undo_redo()

signal remove_requested(index)

func update_midi_track_names(track_names: Array[String]):
	var current_track_name = _cached_track_names[%MidiTrackList.selected]
	%MidiTrackList.clear()
	for i in track_names.size():
		%MidiTrackList.add_item(track_names[i])
		if track_names[i] == current_track_name:
			%MidiTrackList.selected = i
	_cached_track_names = track_names

func set_track_data(data: SongTrackData):
	_track_data = data
	for i in %MidiTrackList.item_count:
		if data.midi_track_name == %MidiTrackList.get_item_text(i):
			%MidiTrackList.select(i)
			break
	%InstrumentList.select(data.instrument)
	%TrackAudioFileField.text = data.audio_file
	%VolumeSpin.set_value_no_signal(data.inactive_volume)

func get_track_data() -> SongTrackData:
	return _track_data


func _on_midi_track_list_item_selected(index: int) -> void:
	undo_redo.create_action("Change MIDI Track")
	undo_redo.add_do_property(_track_data, "midi_track_name", %MidiTrackList.get_item_text(index))
	undo_redo.add_undo_property(_track_data, "midi_track_name", _track_data.midi_track_name)
	undo_redo.commit_action()


func _on_instrument_list_item_selected(index: int) -> void:
	undo_redo.create_action("Change Instrument")
	undo_redo.add_do_property(_track_data, "instrument", index)
	undo_redo.add_undo_property(_track_data, "instrument", _track_data.instrument)
	undo_redo.commit_action()


func _on_track_audio_file_browse_button_pressed() -> void:
	%AudioFileDialog.popup_centered()


func _on_audio_file_dialog_file_selected(path: String) -> void:
	undo_redo.create_action("Change Audio File")
	undo_redo.add_do_property(_track_data, "audio_file", path)
	undo_redo.add_undo_property(_track_data, "audio_file", _track_data.audio_file)
	undo_redo.commit_action()


func _on_volume_spin_value_changed(value: float) -> void:
	undo_redo.create_action("Change Volume")
	undo_redo.add_do_property(_track_data, "inactive_volume", value)
	undo_redo.add_undo_property(_track_data, "inactive_volume", _track_data.inactive_volume)
	undo_redo.commit_action()


func _on_remove_button_pressed() -> void:
	emit_signal("remove_requested", idx)
