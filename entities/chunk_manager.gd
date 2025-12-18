class_name ChunkManager

static var _mutex: Mutex = Mutex.new()
static var _semaphore: Semaphore = Semaphore.new()
static var _thread: Thread
static var _pending_jobs: Array = []
static var _exit_thread := false
static var _running := false
static var _manager_node: SynRoadSongManager
