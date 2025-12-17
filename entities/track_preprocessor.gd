class_name SynRoadTrackPreprocessor

var thread: Thread
var mutex := Mutex.new()
var pending_jobs: Array = []
var completed: Array = []
var running := false

const LANE_GAP := 0.6

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
		"supressed_measures": manager.suppressed_measures,
		"track_reset": manager.fast_track_reset,
		"seconds_per_beat": manager.seconds_per_beat,
		"length_per_beat": manager.length_per_beat,
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
	## map of beat (float) to lane (int)
	var note_map: Dictionary[float,int] = {}
	var valid_note_positions: Array[int] = [job.difficulty_offset, job.difficulty_offset + 2, job.difficulty_offset + 4]
	var tick := 0

	for i in range(job.events.size()):
		var event = job.events[i]
		tick += event.delta_time
		if event is MidiData.NoteOn and event.velocity > 0 and valid_note_positions.has(event.note):
			var beat_position: float = float(tick) / float(job.ticks_per_beat)
			note_map[beat_position] = valid_note_positions.find(event.note)

	note_map.sort()
	var sorted_beats: Array[float] = note_map.keys()
	sorted_beats.sort()
	result["note_map"] = note_map

	var note_times: PackedFloat32Array = []
	var note_positions: PackedVector2Array = [] # Y-value here is Z-position in world space
	var lane_notes: Array = [PackedInt32Array(),PackedInt32Array(),PackedInt32Array()]
	var notes_in_measure: Dictionary[int, PackedInt32Array] = {}

	for i in range(sorted_beats.size()):
		var beat: float = sorted_beats[i]
		# WARN: measure_num is 0-indexed here
		var measure_num: int = int(floor(beat / 4.0))
		var lane: int = note_map[beat]
		var x_pos: float = (lane - 1) * LANE_GAP
		var z_pos: float = (beat * job.length_per_beat)
		note_positions.append(Vector2(x_pos, z_pos))
		if not job.supressed_measures.has(measure_num):
			lane_notes[lane].append(i)
		note_times.append(beat * job.seconds_per_beat)
		if not notes_in_measure.has(measure_num):
			notes_in_measure[measure_num] = []
		(notes_in_measure[measure_num] as Array).append(i)

	assert(note_times.size() == note_positions.size(), "Note times and positions size mismatch!")
	result["note_times"] = note_times
	result["note_positions"] = note_positions

	for i in range(lane_notes.size()):
		(lane_notes[i] as PackedInt32Array).sort()

	result["lane_notes"] = lane_notes

	# can't use a packed array for this since measures may be missing
	var measures: Dictionary = {}
	for m in notes_in_measure.keys():
		assert(!notes_in_measure[m].is_empty(), "Empty measure found in notes_in_measure!")
		var entry = {}
		entry["note_indices"] = notes_in_measure[m]
		entry["note_count"] = notes_in_measure[m].size()
		entry["suppressed"] = job.supressed_measures.has(m)
		measures[m] = entry
	
	var phrases: Dictionary = {}
	for m in measures.keys():
		if measures[m]["suppressed"]:
			continue
		var entry = {}
		entry["start_measure"] = m
		var phrase_measure_count: int = 1
		var phrase_note_indices: Array = measures[m]["note_indices"].duplicate()
		if measures.has(m + 1) and not measures[m + 1]["suppressed"]:
			entry["end_measure"] = m + 1
			phrase_measure_count += 1
			phrase_note_indices.append_array(measures[m + 1]["note_indices"])
		else:
			entry["end_measure"] = m
		entry["measure_count"] = phrase_measure_count
		entry["note_count"] = phrase_note_indices.size()
		phrase_note_indices.sort()
		# TODO: marker position, activation length, next phrase...
		phrases[m] = entry
	
	result["measures"] = measures
	result["phrases"] = phrases


	# var phrases: Array[Dictionary] = []
	# var measures: Array = notes_in_measure.keys()
	# measures.sort()
	# for m in measures:
	# 	if m in job.supressed_measures:
	# 		continue
	# 	var phrase_measure_count: int = 1
	# 	var phrase_beats: Array[float] = []
	# 	phrase_beats.append_array(notes_in_measure[m])
	# 	if notes_in_measure.has(m + 1) and !notes_in_measure[m + 1].is_empty() and \
	# 	  !(job.supressed_measures.has(m + 1)):
	# 		phrase_measure_count += 1
	# 		phrase_beats.append_array(notes_in_measure[m + 1])
	# 	phrase_beats.sort()
	# 	if phrase_beats.is_empty():
	# 		continue
	# 	var first_note_lane: int = note_map[phrase_beats[0]]
	# 	var first_beat: float = phrase_beats[0]
	# 	phrases.append({
	# 		"start_measure": m,
	# 		"measure_count": phrase_measure_count,
	# 		"beats": phrase_beats,
	# 		"first_note_lane": first_note_lane,
	# 		"first_beat": first_beat,
	# 		"score_value": phrase_beats.size(),
	# 	})
	# result["phrases"] = phrases
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
