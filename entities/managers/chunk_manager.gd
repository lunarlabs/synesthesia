extends Node

var thread: Thread
var semaphore: Semaphore
var mutex: Mutex
var exit_thread: bool = false
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
	semaphore = Semaphore.new()
	mutex = Mutex.new()

	thread = Thread.new()
	thread.start(Callable(self , "_thread_func"))

func _thread_func():
	while true:
		semaphore.wait()

		mutex.lock()
		var should_exit = exit_thread
		mutex.unlock()

		if should_exit:
			break
		
		mutex.lock()
		if not job_queue.is_empty():
			var job = job_queue.pop_front()
			mutex.unlock()
			if job.type == REQUEST_CHUNK:
				generate_chunk(job.chunk_idx)
			elif job.type == RECYCLE_CHUNK:
				_recycle_chunk(job.chunk_idx)
		else:
			mutex.unlock()

func generate_chunk(chunk_idx: int):
	for t in _song_node.tracks.size():
		var track_node = _song_node.tracks[t] as SynRoadTrack

		if track_node.chunks[chunk_idx] != null:
			# there's already a chunk here, move on
			continue

		var chunk := Node3D.new()
		chunk.name = "chunk_%d" % chunk_idx


func enqueue_request(chunk_idx: int):
	mutex.lock()
	job_queue.append({
		type = REQUEST_CHUNK,
		chunk_idx = chunk_idx
	})
	mutex.unlock()
	semaphore.post()

func enqueue_recycle(chunk_idx: int):
	mutex.lock()
	job_queue.append({
		type = RECYCLE_CHUNK,
		chunk_idx = chunk_idx
	})
	mutex.unlock()
	semaphore.post()

func _exit_tree():
	mutex.lock()
	exit_thread = true
	mutex.unlock()
	semaphore.post()
	thread.wait_to_finish()
