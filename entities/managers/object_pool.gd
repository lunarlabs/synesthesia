class_name SynRoadObjectPool extends RefCounted

var _stack: Array[Node] = []
var _mutex: Mutex = Mutex.new()
var _scene: PackedScene

func _init(scene: PackedScene):
	_scene = scene

func get_instance() -> Node:
	var instance: Node
	_mutex.lock()
	if _stack.is_empty():
		instance = _scene.instantiate()
	else:
		instance = _stack.pop_back()
	_mutex.unlock()
	return instance

func recycle_instance(instance: Node):
	_mutex.lock()
	var parent = instance.get_parent()
	if is_instance_valid(parent):
		parent.remove_child(instance)
	_stack.append(instance)
	_mutex.unlock()

func clear():
	_mutex.lock()
	var items_to_free = _stack.duplicate()
	_stack.clear()
	_mutex.unlock()
	for item in items_to_free:
		if is_instance_valid(item):
			item.queue_free()