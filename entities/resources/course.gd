@tool

class_name SynRoadCourse
extends Resource

@export_category("Course Info")
@export var course_name: String = "New Course":
	set(value):
		if  course_name != value:
			course_name = value
			emit_changed()

@export_file("*.png", "*.jpg", "*.jpeg") var cover_art: String = "":
	set(value):
		if  cover_art != value:
			cover_art = value
			emit_changed()

@export_category("Course Songs")
@export var course_songs: Array[SongData] = []

@export_category("Final Stage")
@export var final_stage_song: SongData:
	set(value):
		if  final_stage_song != value:
			final_stage_song = value
			emit_changed()
@export_range(2, 4) var final_stage_difficulty: int = 2:
	set(value):
		if  final_stage_difficulty != value:
			final_stage_difficulty = value
			emit_changed()

@export_category("Extra Stage")
@export var extra_stage_song: SongData:
	set(value):
		if  extra_stage_song != value:
			extra_stage_song = value
			emit_changed()
@export_enum("AAA", "AA", "A", "B", "C", "D", "E") var extra_stage_threshold: int = 2:
	set(value):
		if  extra_stage_threshold != value:
			extra_stage_threshold = value
			emit_changed()

@export_category("Course Settings")
@export_enum("Beginner:96", "Intermediate:102", "Advanced:108", "Expert:114")
var min_difficulty: int = 96:
	set(value):
		if  min_difficulty != value:
			min_difficulty = value
			emit_changed()

@export_enum("Don't Care", "Normal", "Constant Drain") var force_energy_mode: int = 0:
	set(value):
		if  force_energy_mode != value:
			force_energy_mode = value
			emit_changed()