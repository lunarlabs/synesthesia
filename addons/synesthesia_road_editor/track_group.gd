extends HBoxContainer

var idx: int
var _cached_track_names: Array[String]

signal data_changed(index)
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
	for i in %MidiTrackList.item_count:
		if data.midi_track_name == %MidiTrackList.get_item_text(i):
			%MidiTrackList.select(i)
			break
	%InstrumentList.select(data.instrument)
	%TrackAudioFileField.text = data.audio_file
	%VolumeSpin.set_value_no_signal(data.inactive_volume)

func get_track_data() -> SongTrackData:
	var result := SongTrackData.new()
	result.audio_file = %TrackAudioFileField.text
	result.inactive_volume = %VolumeSpin.value
	result.midi_track_name = %MidiTrackList.get_item_text(%MidiTrackList.selected)
	result.instrument = %InstrumentList.selected
	return result
