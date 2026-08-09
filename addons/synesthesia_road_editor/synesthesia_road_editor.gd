@tool
extends EditorPlugin

const MainPanel = preload("res://addons/synesthesia_road_editor/main_panel.tscn")

var main_panel_instance: Control

var songs: Dictionary = {}
var packs: Dictionary = {}
var courses: Dictionary = {}

func _enable_plugin() -> void:
	# Add autoloads here.
	pass


func _disable_plugin() -> void:
	# Remove autoloads here.
	pass


func _enter_tree() -> void:
	# Initialization of the plugin goes here.
	main_panel_instance = MainPanel.instantiate()
	EditorInterface.get_editor_main_screen().add_child(main_panel_instance)
	_make_visible(false)


func _exit_tree() -> void:
	# Clean-up of the plugin goes here.
	if main_panel_instance:
		main_panel_instance.queue_free()

func _has_main_screen() -> bool:
	return true

func _make_visible(visible: bool) -> void:
	if main_panel_instance:
		main_panel_instance.visible = visible
	
func _get_plugin_name() -> String:
	return "SynRoad"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("Node", "EditorIcons")
