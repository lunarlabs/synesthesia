@tool
extends Control

var _root_menu_structure: Array = []
var _current_menu_structure: Array = []
var _back_stack: Array = []
var _displayed_menu_structure: Array = []

const ITEM_SPACING_PX := 10

# NOTE: use posmod(x,y) instead of % for relative indexing of menu items because it wraps
# equally in the positive and negative directions.

#region Menu Structure Model
func fetch_menu_structure(force := false):
	if force:
		SongCatalog.make_menu_structure()
	_root_menu_structure = SongCatalog.menu_structure
	_current_menu_structure = _root_menu_structure
	_back_stack = []
	_displayed_menu_structure = []

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
	_update_displayed_menu_structure()

func toggle_category(category_item: Dictionary):
	category_item[&"open"] = not category_item[&"open"]
	_update_displayed_menu_structure()

func navigate_back() -> bool:
	if _back_stack.is_empty():
		return false
	_current_menu_structure = _back_stack.pop_back()
	_update_displayed_menu_structure()
	return true
#endregion