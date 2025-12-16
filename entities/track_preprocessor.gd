class_name SynRoadTrackPreprocessor

var thread: Thread
var mutex := Mutex.new()
var pending_jobs: Array = []
var completed: Array = []
var running := false

func queue_job(
	manager: SynRoadSongManager,
	song_track_index: int,
	events: Array,
	ticks_per_beat:int,):
	mutex.lock()
	pending_jobs.append({
		"song_track_index": song_track_index,
		"events": events,
		"ticks_per_beat": ticks_per_beat,
		"difficulty_offset": manager.difficulty,
		"supressed_measures": manager.supressed_measures,
		"track_reset": manager.fast_track_reset,
	})
	mutex.unlock()
	_start_if_needed()

func _start_if_needed():
	if running:
		return
	running = true
	thread = Thread.new()
	thread.start(_worker)

func _worker(_userdata = null):
	while true:
		var job
		mutex.lock()
		if pending_jobs.is_empty():
			mutex.unlock()
			break
		job = pending_jobs.pop_front()
		mutex.unlock()

		var result = _process_job(job)

		mutex.lock()
		completed.append({
			"track_index": job.song_track_index,
			"result": result,
		})
		mutex.unlock()
	running = false
	return

func _process_job(job:Dictionary):
	var result: Dictionary = {}
	var note_map: Dictionary[float,int] = {}
	var valid_note_positions: Array[int] = [job.difficulty_offset, job.difficulty_offset + 2, job.difficulty_offset + 4]
	var tick := 0

	for i in range(job.events.size()):
		var event = job.events[i]
		tick += event.delta_time
		if event is MidiData.NoteOn and event.velocity > 0 and valid_note_positions.has(event.note):
			var beat_position: float = float(tick) / float(job.ticks_per_beat)
			note_map[beat_position] = valid_note_positions.find(event.note)

	var sorted_beats: Array = note_map.keys()
	sorted_beats.sort()
	result["note_map"] = note_map

	var lane_note_beats: Array = [[],[],[]]
	var beats_in_measure: Dictionary = {}

	for beat_position in sorted_beats:
		var measure_num: int = int(floor(beat_position / 4.0)) + 1
		if not job.supressed_measures.has(measure_num):
			var lane: int = note_map[beat_position]
			lane_note_beats[lane].append(beat_position)
		if not beats_in_measure.has(measure_num):
			beats_in_measure[measure_num] = []
		(beats_in_measure[measure_num] as Array).append(beat_position)

	for i in range(lane_note_beats.size()):
		(lane_note_beats[i] as Array).sort()

	result["lane_note_beats"] = lane_note_beats
	result["beats_in_measure"] = beats_in_measure

	var phrases: Array[Dictionary] = []
	var measures: Array = beats_in_measure.keys()
	measures.sort()
	for m in measures:
		if m in job.supressed_measures:
			continue
		var phrase_measure_count: int = 1
		var phrase_beats: Array[float] = []
		phrase_beats.append_array(beats_in_measure[m])
		if beats_in_measure.has(m + 1) and !beats_in_measure[m + 1].is_empty() and \
		  !(job.supressed_measures.has(m + 1)):
			phrase_measure_count += 1
			phrase_beats.append_array(beats_in_measure[m + 1])
		phrase_beats.sort()
		if phrase_beats.is_empty():
			continue
		var first_note_lane: int = note_map[phrase_beats[0]]
		var first_beat: float = phrase_beats[0]
		phrases.append({
			"start_measure": m,
			"measure_count": phrase_measure_count,
			"beats": phrase_beats,
			"first_note_lane": first_note_lane,
			"first_beat": first_beat,
			"score_value": phrase_beats.size(),
		})
	result["phrases"] = phrases
	return result
		
func take_completed():
	mutex.lock()
	var out = completed.duplicate()
	completed.clear()
	mutex.unlock()
	return out

func wait_for_all():
	if thread:
		thread.wait_to_finish()
	running = false
