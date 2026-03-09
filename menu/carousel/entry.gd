extends NinePatchRect

var carousel_index: int
var current_difficulty: int = 102

const DIFFICULTY_NAMES = {
	96: "Beginner",
	102: "Basic",
	108: "Advanced",
	114: "Expert",
}
const DIFFICULTY_COLORS = {
	96: Color(0.039, 1.0, 0.188),
	102: Color(0.094, 0.659, 1.0),
	108: Color(1.0, 1.0, 0.157),
	114: Color(1.0, 0.1, 0.1)
}
const SONG_ENTRY_BG_COLOR = Color(0.75, 0.75, 0.75, 0.8)
const FOLDER_ENTRY_BG_COLOR = Color(0.149, 0.444, 0.592, 1.0)
const MENU_ENTRY_BG_COLOR = Color(0.311, 0.536, 0.269, 1.0)

@onready var song_container = $Song
@onready var submenu_container = $Submenu
@onready var difficulty_bg = $Song/DifficultyBG
@onready var difficulty_value_label = $Song/DifficultyValueLabel
@onready var play_marker = $Song/PlayMarker
@onready var song_title = $Song/VBoxContainer/TitleLabel
@onready var song_subtitle = $Song/VBoxContainer/SubTitleLabel
@onready var song_difficulty_name = $Song/VBoxContainer/DifficultyNameLabel
@onready var submenu_title = $Submenu/TitleLabel
@onready var submenu_type = $Submenu/TypeLabel

func _ready():
	if carousel_index != 0:
		modulate = Color(0.5, 0.5, 0.5, 1.0)

func update_difficulty(difficulty_offset: int, item: Dictionary):
	if item[&"type"] == &"song_all_difficulties" \
	and not item[&"difficulties"].has(difficulty_offset):
		difficulty_offset = 102 	# TODO: stinky hack since 96 is the only missing difficulty in
									#       freQ songs... for now
	current_difficulty = difficulty_offset
	song_difficulty_name.text = DIFFICULTY_NAMES[difficulty_offset]
	var rating
	match item[&"type"]:
		&"song_all_difficulties":
			rating = item[&"difficulties"].get(difficulty_offset, 0)
		&"song_single_difficulty":
			rating = item[&"difficulty_rating"]
		_: # catch-all for categories, etc.
			rating = 0
	difficulty_value_label.text = "%.1f" % rating
	difficulty_value_label.modulate = DIFFICULTY_COLORS[difficulty_offset]
	difficulty_bg.modulate = DIFFICULTY_COLORS[difficulty_offset]

func update_entry(item: Dictionary):
	match item[&"type"]:
		&"song_all_difficulties":
			self_modulate = SONG_ENTRY_BG_COLOR
			song_container.show()
			submenu_container.hide()
			song_title.text = item[&"name"]
			if item[&"sub_title"]:
				song_subtitle.text = item[&"sub_title"]
				song_subtitle.show()
			else:
				song_subtitle.hide()
			song_difficulty_name.hide()
			update_difficulty(current_difficulty, item)
		
		&"song_single_difficulty":
			self_modulate = SONG_ENTRY_BG_COLOR
			song_container.show()
			submenu_container.hide()
			song_title.text = item[&"name"]
			if item[&"sub_title"]:
				song_subtitle.text = item[&"sub_title"]
				song_subtitle.show()
			else:
				song_subtitle.hide()
			song_difficulty_name.show()
			update_difficulty(item[&"difficulty_offset"], item)
		
		&"submenu":
			self_modulate = MENU_ENTRY_BG_COLOR
			song_container.hide()
			submenu_container.show()
			submenu_title.text = item[&"name"]
			submenu_type.text = item[&"type"]
		
		&"category":
			self_modulate = FOLDER_ENTRY_BG_COLOR
			song_container.hide()
			submenu_container.show()
			submenu_title.text = item[&"name"]
			submenu_type.text = "%d songs" % item[&"children"].size() if item[&"children"].size() != 1 else "1 song"
