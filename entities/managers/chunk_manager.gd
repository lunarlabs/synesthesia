extends Node

var thread: Thread
var semaphore: Semaphore
var mutex: Mutex
var exit_thread: bool = false
var requested_chunk: int
var _note_scene: PackedScene = preload("res://entities/note.tscn")
var _measure_scene: PackedScene = preload("res://entities/measure.tscn")
var manager_node: SynRoadSongManager
var _note_stack: Array = []
var _measure_stack: Array = []
var job_queue: Array = []

enum {REQUEST_CHUNK, RECYCLE_CHUNK}

func _ready():
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
				_generate_chunk(job.chunk_idx)
			elif job.type == RECYCLE_CHUNK:
				_recycle_chunk(job.chunk_idx)
		else:
			mutex.unlock()

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