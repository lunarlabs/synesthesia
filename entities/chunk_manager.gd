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

		var chunk_idx = current_job.y

		var track_node = manager_node.song_instance.tracks[current_job.x] as SynRoadTrack
		if track_node.chunks[chunk_idx] != null:
			# The chunk is already loaded
			continue
		var z_scale = manager_node.length_multiplier
		var chunk := Node3D.new()

		for i in track_node.track_data.measures_in_chunks[chunk_idx]:
			var new_measure = _measure_scene.instantiate()

	_running = false
	return

static func request_chunk(track: int, chunk: int):
	assert(manager_node, "No SongManager node was assigned to ChunkManager")
	_mutex.lock()
	_pending_jobs.append(Vector2i(track,chunk))
	_mutex.unlock()
	_semaphore.post()
	
