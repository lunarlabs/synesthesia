extends Node

var thread: Thread
var _semaphore: Semaphore
var _mutex: Mutex
var _exit_thread: bool = false
var requested_chunk: int
var _note_scene: PackedScene = preload("res://entities/note.tscn")
var _measure_scene: PackedScene = preload("res://entities/measure.tscn")
var _manager_node: SynRoadSongManager
var _song_node: SynRoadSong
var _note_stack: Array = []
var _measure_stack: Array = []
var _z_scale: float
var _measure_positions: PackedFloat32Array
var _suppressed_measures: Array[bool]
var job_queue: Array = []

enum {REQUEST_CHUNK, RECYCLE_CHUNK}

func _ready():
	_song_node = get_parent()
	_manager_node = _song_node.get_parent()
	_z_scale = _manager_node.length_multiplier
	_measure_positions = _manager_node.measure_positions
	_suppressed_measures = _manager_node.suppressed_measures
	_semaphore = Semaphore.new()
	_mutex = Mutex.new()

	thread = Thread.new()
	thread.start(Callable(self , "_thread_func"))

func _thread_func():
	while true:
		_semaphore.wait()

		_mutex.lock()
		var should_exit = _exit_thread
		_mutex.unlock()

		if should_exit:
			break
		
		_mutex.lock()
		if not job_queue.is_empty():
			var job = job_queue.pop_front()
			_mutex.unlock()
			if job.type == REQUEST_CHUNK:
				generate_chunk(job.chunk_idx)
			elif job.type == RECYCLE_CHUNK:
				_recycle_chunk(job.chunk_idx)
		else:
			_mutex.unlock()

func generate_chunk(chunk_idx: int):
	var track_count = _song_node.tracks.size()
	var worker_callable = Callable(self, "_chunk_generation_worker").bind(chunk_idx)
	var task_id = WorkerThreadPool.add_group_task(worker_callable, track_count)
	WorkerThreadPool.wait_for_group_task_completion(task_id)


func _chunk_generation_worker(track_idx: int, chunk_idx: int):
	var track_node = _song_node.tracks[track_idx] as SynRoadTrack
	if track_node.chunks[chunk_idx] != null:
		# there's already a chunk here, move on
		return

	var track_data = track_node.track_data
	var phrase_measures: Array[int] = []
	var current_p_index = track_node.current_phrase_index
	if current_p_index < track_data.phrase_lengths[current_p_index]:
		for i in track_data.phrase_lengths[current_p_index]:
			phrase_measures.append(track_data.phrase_starts[current_p_index] + i)

	var chunk := Node3D.new()
	chunk.name = "chunk_%d" % chunk_idx

	var new_measure_nodes: Dictionary[int, Node3D] = {}
	var new_note_nodes: Dictionary[int, SynRoadNote] = {}

	for i in track_data.measures_in_chunks[chunk_idx]:
		if not _manager_node.suppressed_measures[i]:
			var new_measure: Node3D

			_mutex.lock()
			if not _measure_stack.is_empty():
				new_measure = _measure_stack.pop_back() as Node3D
			_mutex.unlock()

			if not is_instance_valid(new_measure):
				new_measure = _measure_scene.instantiate() as Node3D

#			new_measure.name = "measure_%d" % i
			var cube = new_measure.get_node("track_geometry/Cube")
			cube.set_instance_shader_parameter("this_track", track_idx)
			cube.set_instance_shader_parameter("measure_tint", track_node.lane_tint)
			cube.set_instance_shader_parameter("phrase", i in phrase_measures)
			cube.show()
			new_measure.position.z = _manager_node.measure_positions[i]
			new_measure.scale.z = _z_scale
			new_measure_nodes[i] = new_measure
			chunk.add_child(new_measure)

		for j in track_data.notes_in_measure[i]:
			var new_note: SynRoadNote

			_mutex.lock()
			if not _note_stack.is_empty():
				new_note = _note_stack.pop_back() as SynRoadNote
			_mutex.unlock()

			if not is_instance_valid(new_note):
				new_note = _note_scene.instantiate() as SynRoadNote

			new_note.request_ready()
#			new_note.name = "note_%d" % j
			new_note.capsule_material = track_node.instrument_note_material
			new_note.ghost_material = track_node.instrument_ghost_material
			new_note.suppressed = _manager_node.suppressed_measures[i]
			new_note.position.x = track_data.note_positions[j].x
			new_note.position.z = track_data.note_positions[j].y
			if i < track_node.reset_measure:
				new_note.blast(false)
			new_note_nodes[j] = new_note
			chunk.add_child(new_note)
	call_deferred("_apply_chunk", track_idx, chunk_idx, chunk, new_measure_nodes, new_note_nodes)

func _apply_chunk(track_idx: int, chunk_idx: int, chunk: Node3D, measures: Dictionary[int, Node3D], notes: Dictionary[int, SynRoadNote]):
		var track_node = _song_node.tracks[track_idx] as SynRoadTrack

		for i in measures:
			track_node.measure_nodes[i] = measures[i]
		for i in notes:
			track_node.note_nodes[i] = notes[i]

		track_node.chunks[chunk_idx] = chunk
		track_node.add_child(chunk)

func _recycle_chunk(chunk_idx: int):
	# TODO: remove all nodes with chunk_idx from all tracks then place them in object pool.
	pass

func enqueue_request(chunk_idx: int):
	_mutex.lock()
	job_queue.append({
		type = REQUEST_CHUNK,
		chunk_idx = chunk_idx
	})
	_mutex.unlock()
	_semaphore.post()

func enqueue_recycle(chunk_idx: int):
	_mutex.lock()
	job_queue.append({
		type = RECYCLE_CHUNK,
		chunk_idx = chunk_idx
	})
	_mutex.unlock()
	_semaphore.post()

func _exit_tree():
	_mutex.lock()
	_exit_thread = true
	_mutex.unlock()
	_semaphore.post()
	thread.wait_to_finish()
