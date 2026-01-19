extends Node

var _mutex: Mutex = Mutex.new()
var _pending_jobs: Array[int] = []
var _note_scene: PackedScene = preload("res://entities/note.tscn")
var _measure_scene: PackedScene = preload("res://entities/measure.tscn")
var manager_node: SynRoadSongManager
var _note_stack: Array = []
var _measure_stack: Array = []

signal queue_empty

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

@warning_ignore("unused_parameter")
func _process(delta: float) -> void:
	while not _pending_jobs.is_empty():
		for job in _pending_jobs:
			if WorkerThreadPool.is_task_completed(job):
				WorkerThreadPool.wait_for_task_completion(job)
				_pending_jobs.erase(job)
				break # Restart the while loop to avoid iterator invalidation
	set_process(false)
	emit_signal("queue_empty")

func generate_chunk(track_idx: int, chunk_idx: int):
	var time_start = Time.get_ticks_usec()
	print("generating chunk %d at track %d" % [track_idx, chunk_idx])
	var track_node = manager_node.song_instance.tracks[track_idx] as SynRoadTrack

	if track_node.chunks[chunk_idx] != null:
		print("already loaded")
		# The chunk is already loaded
		return
	var track_data = track_node.track_data
	var phrase_measures: Array[int] = []
	var current_p_index = track_node.current_phrase_index
	if current_p_index < track_data.phrase_lengths.size():
		for i in track_data.phrase_lengths[current_p_index]:
			phrase_measures.append(track_data.phrase_starts[current_p_index] + i)
	var z_scale = manager_node.length_multiplier
	var chunk := Node3D.new()
	chunk.name = "chunk_%d" % chunk_idx

	var new_measure_nodes: Dictionary[int, Node3D] = {}
	var new_note_nodes: Dictionary[int, SynRoadNote] = {}

	for i in track_data.measures_in_chunks[chunk_idx]:
		if not manager_node.suppressed_measures[i] or (i < track_node.reset_measure):
			var new_measure: Node3D
			if not _measure_stack.is_empty():
				_mutex.lock()
				new_measure = _measure_stack.pop_back() as Node3D
				_mutex.unlock()
				if not new_measure:
					new_measure = _measure_scene.instantiate() as Node3D
			else:
				new_measure = _measure_scene.instantiate() as Node3D
			new_measure.name = "measure_%d" % i
			new_measure.get_node("track_geometry").get_node("Cube") \
			.set_instance_shader_parameter("this_track", track_idx)
			new_measure.get_node("track_geometry").get_node("Cube") \
			.set_instance_shader_parameter("measure_tint", track_node.lane_tint)
			new_measure.get_node("track_geometry").get_node("Cube") \
			.set_instance_shader_parameter("phrase", i in phrase_measures)
			new_measure.get_node("track_geometry").get_node("Cube").show()
			new_measure.position.z = manager_node.measure_positions[i]
			new_measure.scale.z = z_scale
			new_measure_nodes[i] = new_measure
			chunk.add_child(new_measure)

		for j in track_data.notes_in_measure[i]:
			var new_note: SynRoadNote
			if not _note_stack.is_empty():
				_mutex.lock()
				new_note = _note_stack.pop_back() as SynRoadNote
				_mutex.unlock()
				if not new_note:
					new_note = _note_scene.instantiate() as SynRoadNote
				new_note.request_ready()
			else:
				new_note = _note_scene.instantiate() as SynRoadNote
			new_note.name = "note_%d" % j
			new_note.capsule_material = track_node.instrument_note_material
			new_note.ghost_material = track_node.instrument_ghost_material
			new_note.suppressed = manager_node.suppressed_measures[i]
			new_note.position.x = track_data.note_positions[j].x
			new_note.position.z = track_data.note_positions[j].y
			if i < track_node.reset_measure:
				new_note.blast(false)
			new_note_nodes[j] = new_note
			chunk.add_child(new_note)
	var time_end = Time.get_ticks_usec()
	print("generated chunk %d at track %d in %d microseconds" % [track_idx, chunk_idx, time_end - time_start])
	call_deferred("_apply_chunk_data", track_idx, chunk_idx, chunk, new_measure_nodes, new_note_nodes)

func _apply_chunk_data(track_idx: int, chunk_idx: int, chunk: Node3D, measures: Dictionary[int, Node3D], notes: Dictionary[int, SynRoadNote]):
	if !is_instance_valid(manager_node) or !is_instance_valid(manager_node.song_instance):
		return
	
	var track_node = manager_node.song_instance.tracks[track_idx] as SynRoadTrack
	for i in measures:
		track_node.measure_nodes[i] = measures[i]
	for i in notes:
		track_node.note_nodes[i] = notes[i]

	track_node.chunks[chunk_idx] = chunk
	track_node.add_child(chunk)

func request_chunk(track: int, chunk: int):
	assert(manager_node, "No SongManager node was assigned to ChunkManager")
	var chunk_request: Callable = Callable(self, "generate_chunk").bind(track, chunk)
	var job_id = WorkerThreadPool.add_task(chunk_request)
	_pending_jobs.append(job_id)
	set_process(true)

func recycle_chunk(chunk: Node3D):
	var time_start = Time.get_ticks_usec()
	if chunk.is_inside_tree():
		chunk.get_parent().remove_child(chunk)
	for child in chunk.get_children():
		assert(!child.is_inside_tree(), "Child nodes must be removed from scene tree before recycling")
		if child is SynRoadNote:
			chunk.remove_child(child)
			_mutex.lock()
			_note_stack.append(child)
			_mutex.unlock()
		elif child is Node3D and child.name.begins_with("measure_"):
			chunk.remove_child(child)
			_mutex.lock()
			_measure_stack.append(child)
			_mutex.unlock()
	chunk.queue_free()
	var time_end = Time.get_ticks_usec()
	print("recycled chunk in %d microseconds" % [time_end - time_start])
