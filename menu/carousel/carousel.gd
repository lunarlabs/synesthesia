extends Control

var _root_menu_structure: Array = []
var _current_menu_structure: Array = []
var _back_stack: Array = []
var _displayed_menu_structure: Array = []
var _lamp_status: Dictionary = {}

var _current_item_index: int = 0
var _current_open_folder: int = -1
var _current_difficulty: int = 102

# Breadcrumb tracking for session state save/restore.
var _current_submenu_name: String = ""
var _current_category_name: String = ""

var current_item: Dictionary:
	get:
		return _displayed_menu_structure[_get_index_at_offset()]

const ITEM_SPACING_PX := 6
const COL_OFFSET_PX := 20
const ENTRY_SCENE: PackedScene = preload("res://menu/carousel/entry.tscn")
const SCROLL_ANIM_DURATION := 0.15

var _scroll_tween: Tween
var _entry_height: float

@onready var entries = $Entries

signal selection_changed(reference: Dictionary)
signal song_selected(song_folder: String, difficulty: int)

# NOTE: use posmod(x,y) instead of % for relative indexing of menu items because it wraps
# equally in the positive and negative directions.

#region Menu Structure Model
func fetch_menu_structure(force := false):
	if force:
		SongCatalog.make_menu_structure()
	_lamp_status = SessionManager.get_lamps()
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
			switch_category(item)
		&"song_all_difficulties":
			song_selected.emit(item[&"folder_id"], -1)
		&"song_single_difficulty":
			song_selected.emit(item[&"folder_id"], item[&"difficulty_offset"])
		&"challenge_menu":
			pass # TODO: implement changing to challenge course menu whenever I write the damn thing

func navigate_into_submenu(submenu_item: Dictionary, emit := true):
	_back_stack.push_back([_current_menu_structure, _current_item_index])
	_current_menu_structure = submenu_item[&"children"]
	_current_submenu_name = submenu_item[&"name"]
	_current_category_name = ""
	_current_item_index = 0
	_update_displayed_menu_structure()
	update_carousel(emit)

func toggle_category(category_item: Dictionary):
	category_item[&"open"] = not category_item[&"open"]
	_update_displayed_menu_structure()
	update_carousel(false)

func switch_category(category_item: Dictionary):
	for i in _current_menu_structure.size():
		var item = _current_menu_structure[i]
		if item[&"type"] == &"category" and item[&"open"]:
			item[&"open"] = false
			if _current_item_index > i:
				_current_item_index -= item[&"children"].size()
			_update_displayed_menu_structure()
	_current_open_folder = _current_item_index
	category_item[&"open"] = true
	_current_category_name = category_item[&"name"]
	_update_displayed_menu_structure()
	update_carousel(false)
		
func navigate_back() -> bool:
	if _back_stack.is_empty():
		return false
	var previous_menu_structure = _back_stack.pop_back()
	_current_menu_structure = previous_menu_structure[0]
	_current_item_index = previous_menu_structure[1]
	_current_category_name = ""
	if _back_stack.is_empty():
		_current_submenu_name = ""
	_update_displayed_menu_structure()
	update_carousel()
	return true
#endregion

func update_carousel(emit := true, animate_direction: int = 0):
	for i in range(entries.get_child_count()):
		var entry = entries.get_child(i)
		var item_index = posmod(_current_item_index + entry.carousel_index, _displayed_menu_structure.size())
		entry.current_difficulty = _current_difficulty
		entry.update_entry(_displayed_menu_structure[item_index])
	if animate_direction != 0:
		_animate_scroll(animate_direction)
	if emit:
		emit_currently_selected()

func _animate_scroll(direction: int) -> void:
	if _scroll_tween and _scroll_tween.is_valid():
		_scroll_tween.kill()
	_scroll_tween = create_tween().set_parallel(true)
	_scroll_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	var offset_y := _entry_height * direction # positive = items come from below
	for i in range(entries.get_child_count()):
		var entry = entries.get_child(i)
		var home_y: float = entry.home_y
		var home_left_offset: float = entry.home_left_offset
		entry.position.y = home_y + offset_y
		entry.offset_left = abs(entry.carousel_index + direction) * COL_OFFSET_PX
		_scroll_tween.tween_property(entry, "position:y", home_y, SCROLL_ANIM_DURATION)
		_scroll_tween.tween_property(entry, "offset_left", home_left_offset, SCROLL_ANIM_DURATION)
		# Animate modulate: selected entry (carousel_index == 0) brightens, others dim
		var target_color := Color.WHITE if entry.carousel_index == 0 else Color(0.5, 0.5, 0.5, 1.0)
		_scroll_tween.tween_property(entry, "modulate", target_color, SCROLL_ANIM_DURATION)

func emit_currently_selected():
	selection_changed.emit(current_item)

func _get_index_at_offset(value: int = 0):
	return posmod(_current_item_index + value, _displayed_menu_structure.size())

func _ready():
	# Find out how many entry instances will be needed
	# We need enough to fill the viewport, plus a few extra for scrolling
	var instance = ENTRY_SCENE.instantiate()
	var total_height = instance.get_size().y + ITEM_SPACING_PX
	_entry_height = total_height
	var viewport_height = get_viewport().get_visible_rect().size.y
	var num_entries = int(viewport_height / total_height) + 1
	if num_entries % 2 == 0:
		num_entries += 1
	var entry_y_pos = ((viewport_height - num_entries * total_height) + ITEM_SPACING_PX) / 2
	for i in range(num_entries):
		if i != 0:
			instance = ENTRY_SCENE.instantiate()
		instance.position.y = entry_y_pos
		instance.home_y = entry_y_pos
		instance.anchor_right = 1.0
		instance.offset_right = 0.0
		@warning_ignore("integer_division")
		var index = - num_entries / 2 + i
		instance.carousel_index = index
		instance.home_left_offset = abs(instance.carousel_index) * COL_OFFSET_PX
		instance.offset_left = instance.home_left_offset
		instance.gui_input.connect(_on_entry_gui_input.bind(index))
		instance.name = "Entry%d" % instance.carousel_index
		entries.add_child(instance)
		entry_y_pos += total_height
	fetch_menu_structure(false)

func _unhandled_input(event: InputEvent):
	if get_viewport().gui_get_focus_owner() in get_parent().subscreen_buttons \
	or %ModifierContainer.visible:
		return
	if event.is_action_pressed("ui_up"):
		get_viewport().set_input_as_handled()
		_current_item_index = _get_index_at_offset(-1)
		update_carousel(true, -1)
	elif event.is_action_pressed("ui_down"):
		get_viewport().set_input_as_handled()
		_current_item_index = _get_index_at_offset(1)
		update_carousel(true, 1)
	elif event.is_action_pressed("ui_accept"):
		select_item(current_item)
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		navigate_back()
		update_carousel()

func _on_entry_gui_input(event: InputEvent, index: int):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if get_viewport().gui_get_focus_owner() in get_parent().subscreen_buttons:
			get_viewport().gui_get_focus_owner().release_focus()
		if index == 0:
			var item = _displayed_menu_structure[posmod(_current_item_index, _displayed_menu_structure.size())]
			select_item(item)
			update_carousel()
		else:
			_current_item_index = _get_index_at_offset(index)
			update_carousel()

func _exit_tree() -> void:
	_save_state_to_session()

func _save_state_to_session() -> void:
	if _displayed_menu_structure.is_empty():
		return
	var current: Dictionary = _displayed_menu_structure[posmod(_current_item_index, _displayed_menu_structure.size())]
	SessionManager.previous_select_options = {
		&"submenu_name": _current_submenu_name,
		&"category_name": _current_category_name,
		&"item_name": current.get(&"folder_id", current.get(&"name", "")),
		&"difficulty": _current_difficulty,
	}

func restore_state_from_session() -> void:
	var opts := SessionManager.previous_select_options
	if opts.is_empty():
		return
	# Restore difficulty before the first update_carousel() in _ready().
	if opts.has(&"difficulty"):
		_current_difficulty = opts[&"difficulty"]
	# Navigate into the saved submenu, if any.
	if opts.has(&"submenu_name") and not (opts[&"submenu_name"] as String).is_empty():
		for item: Dictionary in _root_menu_structure:
			if item[&"name"] == opts[&"submenu_name"]:
				navigate_into_submenu(item, false)
				break
	# Open the saved category, if any.
	if opts.has(&"category_name") and not (opts[&"category_name"] as String).is_empty():
		for item: Dictionary in _current_menu_structure:
			if item[&"type"] == &"category" and item[&"name"] == opts[&"category_name"]:
				switch_category(item)
				break
	# Seek to the saved item by folder_id / name.
	if opts.has(&"item_name"):
		var target := opts[&"item_name"] as String
		for i: int in _displayed_menu_structure.size():
			var item: Dictionary = _displayed_menu_structure[i]
			if item.get(&"folder_id", item.get(&"name", "")) == target:
				_current_item_index = i
				break

func _on_song_select_difficulty_changed(difficulty: int) -> void:
	_current_difficulty = difficulty
	update_carousel(false)
