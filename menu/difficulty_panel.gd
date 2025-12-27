extends Control

@export_color_no_alpha var base_color = Color(0.25,0.25,0.25)
@export_color_no_alpha var selected_color = Color(1,1,1)
@export var difficulty_name: String = "Difficulty"
@export_range(0, 11, 0.1) var difficulty_value: float = 10

@onready var name_lbl = $DifficultyNameLabel
@onready var value_lbl = $DifficultyValueLabel
@onready var unselected_tex = $ButtonTexture
@onready var selected_tex = $SelectedTexture

var _selected: bool = false

var selected:
	get:
		return _selected
	set(v):
		_selected = v
		selected_tex.visible = v
		unselected_tex.visible = !v
		name_lbl.modulate = Color.WHITE if v else selected_color

func _ready():
	update()
	
func update():
	name_lbl.text = difficulty_name
	value_lbl.text = "%.1f" % difficulty_value if difficulty_value > 0 else "--"
	if difficulty_value <= 0:
		unselected_tex.modulate = Color(0.25, 0.25, 0.25)
		name_lbl.modulate = Color(0.5,0.5,0.5)
		value_lbl.modulate = Color(0.5,0.5,0.5)
	else:
		unselected_tex.modulate = base_color
		selected_tex.modulate = selected_color
		name_lbl.modulate = Color.WHITE if _selected else selected_color
		value_lbl.modulate = selected_color
	unselected_tex.modulate.a = 0.5
