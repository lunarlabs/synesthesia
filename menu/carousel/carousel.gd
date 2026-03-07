extends Control

var _root_menu_structure: Array = []
var _current_menu_structure: Array = []
var _back_stack: Array = []
var _displayed_menu_structure: Array = []

var _current_item_index: int = 0
var _current_difficulty: int = 102

const ITEM_SPACING_PX := 6
const COL_OFFSET_PX := 20
const ENTRY_SCENE: PackedScene = preload("res://menu/carousel/entry.tscn")

signal selection_changed(type: String, reference: String)
signal song_selected(song_data: SongData, difficulty: int)

# NOTE: use posmod(x,y) instead of % for relative indexing of menu items because it wraps
# equally in the positive and negative directions.

#region Menu Structure Model
func fetch_menu_structure(force := false):
	if force:
		SongCatalog.make_menu_structure()
	_root_menu_structure = SongCatalog.menu_structure
	_current_menu_structure = _root_menu_structure
	_back_stack = []
	_update_displayed_menu_structure()

func _update_displayed_menu_structure():
	_displayed_menu_structure = []
	for i in range(_current_menu_structure.size()):
		var item = _current_menu_structure[i]
		_displayed_menu_structure.append(item)
		if item[&"type"] == &"category" and item[&"open"] == true:
			for j in range(item[&"children"].size()):
				_displayed_menu_structure.append(item[&"children"][j])

func select_item(item: Dictionary):
	match item[&"type"]:
		&"submenu":
			navigate_into_submenu(item)
		&"category":
			toggle_category(item)
		# song_all_difficulties, song_single_difficulty — handled elsewhere

func navigate_into_submenu(submenu_item: Dictionary):
	_back_stack.push_back(_current_menu_structure)
	_current_menu_structure = submenu_item[&"children"]
	_current_item_index = 0
	_update_displayed_menu_structure()

func toggle_category(category_item: Dictionary):
	category_item[&"open"] = not category_item[&"open"]
	_update_displayed_menu_structure()

func switch_category(category_item: Dictionary):
	for i in _current_menu_structure.size():
		if _current_menu_structure[i][&"type"] == &"category":
			_current_menu_structure[i][&"open"] = false
	category_item[&"open"] = true
	_update_displayed_menu_structure()
		
func navigate_back() -> bool:
	if _back_stack.is_empty():
		return false
	_current_menu_structure = _back_stack.pop_back()
	_update_displayed_menu_structure()
	return true
#endregion

func _ready():
	# Find out how many entry instances will be needed
	# We need enough to fill the viewport, plus a few extra for scrolling
	var instance = ENTRY_SCENE.instantiate()
	var total_height = instance.get_size().y + ITEM_SPACING_PX
	var viewport_height = get_viewport().get_visible_rect().size.y
	var num_entries = int(viewport_height / total_height) + 1
	if num_entries % 2 == 0:
		num_entries += 1
	var entry_y_pos = ((viewport_height - num_entries * total_height) + ITEM_SPACING_PX) / 2
	for i in range(num_entries):
		if i != 0:
			instance = ENTRY_SCENE.instantiate()
		instance.position.y = entry_y_pos
		instance.anchor_right = 1.0
		instance.offset_right = 0.0
		@warning_ignore("integer_division")
		instance.carousel_index = - num_entries / 2 + i
		instance.offset_left = abs(instance.carousel_index) * COL_OFFSET_PX
		instance.gui_input.connect(_on_entry_gui_input.bind(instance))
		add_child(instance)
		entry_y_pos += total_height
	fetch_menu_structure(true)
	update_carousel()

func update_carousel():
	for i in range(get_child_count()):
		var entry = get_child(i)
		var item_index = posmod(_current_item_index + entry.carousel_index, _displayed_menu_structure.size())
		entry.current_difficulty = _current_difficulty
		entry.update_entry(_displayed_menu_structure[item_index])

func _unhandled_input(event: InputEvent):
	if get_viewport().gui_get_focus_owner() in get_parent().subscreen_buttons:
		return
	if event.is_action_pressed("ui_up"):
		get_viewport().set_input_as_handled()
		_current_item_index = posmod(_current_item_index - 1, _displayed_menu_structure.size())
		update_carousel()
	elif event.is_action_pressed("ui_down"):
		get_viewport().set_input_as_handled()
		_current_item_index = posmod(_current_item_index + 1, _displayed_menu_structure.size())
		update_carousel()
	elif event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		var item = _displayed_menu_structure[posmod(_current_item_index, _displayed_menu_structure.size())]
		select_item(item)
		update_carousel()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		navigate_back()
		update_carousel()

func _on_entry_gui_input(event: InputEvent, entry: Control):
	pass


func _on_song_select_difficulty_changed(difficulty: int) -> void:
	pass # Replace with function body.
