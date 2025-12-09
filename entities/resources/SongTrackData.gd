@tool
extends Resource
class_name SongTrackData

## The exact name of the track in the MIDI file
## (e.g. "T1 CATCH:D:DRUMS")
@export var midi_track_name:String

## The instrument type of the track
@export_enum("Drums", "Bass", "Guitar", "Synth", "Vocals", "FX") var instrument = 0

## The audio file of the track
@export_file("*.wav") var audio_file: String
