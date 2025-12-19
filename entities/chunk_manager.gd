class_name ChunkManager

static var _mutex: Mutex = Mutex.new()
static var _semaphore: Semaphore = Semaphore.new()
static var _thread: Thread
static var _pending_jobs: Array[Vector2i] = []
static var _exit_thread := false
static var _running := false
static var manager_node: SynRoadSongManager

static func start_if_needed():
	if _running:
		return
	_running = true
	_exit_thread = false
	_thread = Thread.new()
	_thread.start(_worker)

static func _worker(_userdata = null):
	while true:
		_semaphore.wait()

		_mutex.lock()
		var should_exit = _exit_thread
		_mutex.unlock()

		if should_exit:
			break
	_running = false
	return

static func request_chunk(track: int, chunk: int):
	assert(manager_node, "No SongManager node was assigned to ChunkManager")
