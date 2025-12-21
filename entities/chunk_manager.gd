class_name ChunkManager

static var _mutex: Mutex = Mutex.new()
static var _semaphore: Semaphore = Semaphore.new()
static var _thread: Thread
static var _pending_jobs: Array[Vector2i] = []
static var _exit_thread := false
static var _running := false
static var _note_scene: PackedScene
static var _measure_scene: PackedScene
static var manager_node: SynRoadSongManager

static func start_if_needed():
	if _running:
		return
	_running = true
	_exit_thread = false
	_thread = Thread.new()
	_thread.start(_worker)

static func stop():
	_mutex.lock()
	_exit_thread = true
	_mutex.unlock()
	_semaphore.post()
	_thread.wait_to_finish()
	_pending_jobs.clear()

static func _worker(_userdata = null):
	if _note_scene == null:
		_note_scene = load("res://entities/note.tscn")
	if _measure_scene == null:
		_measure_scene = load("res://entities/measure.tscn")
	while true:
		_semaphore.wait()

		_mutex.lock()
		var should_exit = _exit_thread
		_mutex.unlock()

		if should_exit:
			break
		
		_mutex.lock()
		var current_job = _pending_jobs.pop_front()
		_mutex.unlock()
		print("Chunk worker thread working on " + str(current_job))

		var track_idx = current_job.x
		var chunk_idx = current_job.y

		var track_node = manager_node.song_instance.tracks[track_idx] as SynRoadTrack
		var track_data = track_node.track_data
		if track_node.chunks[chunk_idx] != null:
			# The chunk is already loaded
			continue
		var z_scale = manager_node.length_multiplier
		var chunk := Node3D.new()
		chunk.name = "chunk_%d" % chunk_idx

		for i in track_data.measures_in_chunks[chunk_idx]:
			if not manager_node.suppressed_measures[i] or (i < track_node.reset_measure):
				var new_measure = _measure_scene.instantiate() as Node3D
				new_measure.name = "measure_%d" % i
				new_measure.get_node("track_geometry").get_node("Cube").set_instance_shader_parameter("this_track", track_idx)
				new_measure.get_node("track_geometry").get_node("Cube").set_instance_shader_parameter("measure_tint", track_node.lane_tint)
				new_measure.get_node("track_geometry").get_node("Cube").set_instance_shader_parameter("phrase", false)
				new_measure.position.z = manager_node.measure_positions[i]
				new_measure.scale.z = z_scale
				track_node.measure_nodes[i] = new_measure
				chunk.add_child(new_measure)

			for j in track_data.notes_in_measure[i]:
				var new_note = _note_scene.instantiate() as SynRoadNote
				new_note.name = "note_%d" % j
				new_note.capsule_material = track_node.instrument_note_material
				new_note.ghost_material = track_node.instrument_ghost_material
				new_note.suppressed = manager_node.suppressed_measures[i]
				new_note.position.x = track_data.note_positions[j].x
				new_note.position.z = track_data.note_positions[j].y
				if i < track_node.reset_measure:
					new_note.blast(false)
				track_node.note_nodes[j] = new_note
				chunk.add_child(new_note)
		
		track_node.chunks[chunk_idx] = chunk
		track_node.add_child.call_deferred(chunk)

	_running = false
	return

static func request_chunk(track: int, chunk: int):
	assert(manager_node, "No SongManager node was assigned to ChunkManager")
#	print("Track %d requests chunk %d" % [track, chunk])
	_mutex.lock()
	_pending_jobs.append(Vector2i(track,chunk))
	_mutex.unlock()
	_semaphore.post()
	
