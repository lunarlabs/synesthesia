@tool
extends Control

var _root_menu_structure: Array = []
var _current_menu_structure: Array = []
var _back_stack: Array = []
var _displayed_menu_structure: Array = []

# NOTE: use posmod(x,y) instead of % for relative indexing of menu items because it wraps
# equally in the positive and negative directions.

func fetch_menu_structure():
	_root_menu_structure = SongCatalog.menu_structure
