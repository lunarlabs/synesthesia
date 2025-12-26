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
		"chunk_count": manager.chunk_count,
		"suppressed_measures": manager.suppressed_measures,
		"track_reset": manager.fast_track_reset,
		"seconds_per_beat": manager.seconds_per_beat,
		"length_per_beat": manager.length_per_beat,
		"total_measures": manager.total_measures,
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
	var result: SynRoadTrack.GameplayTrackData = SynRoadTrack.GameplayTrackData.new()
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
	result.note_map = note_map

	var note_times: PackedFloat32Array = []
	var note_positions: PackedVector2Array = [] # Y-value here is Z-position in world space
	var lane_notes: Array = [PackedInt32Array(),PackedInt32Array(),PackedInt32Array()]
	var notes_in_measure: Dictionary[int, PackedInt32Array] = {}

	for i in range(sorted_beats.size()):
		var beat: float = sorted_beats[i]
		# WARN: measure_num is 0-indexed here
		var measure_num: int = int(floor(beat / 4.0))
		if measure_num < job.total_measures:
			var lane: int = note_map[beat]
			var x_pos: float = (lane - 1) * LANE_GAP
			var z_pos: float = (beat * job.length_per_beat)
			note_positions.append(Vector2(x_pos, z_pos))
			if not job.suppressed_measures[measure_num]:
				lane_notes[lane].append(i)
			note_times.append(beat * job.seconds_per_beat)
			if not notes_in_measure.has(measure_num):
				notes_in_measure[measure_num] = PackedInt32Array()
			notes_in_measure[measure_num].append(i)

	assert(note_times.size() == note_positions.size(), "Note times and positions size mismatch!")
	result.note_times = note_times
	result.note_positions = note_positions
	result.notes_in_measure = notes_in_measure

	for i in range(lane_notes.size()):
		(lane_notes[i] as PackedInt32Array).sort()

	result["lane_notes"] = lane_notes

	var measure_note_counts: Dictionary[int,int] = {}
	var measures_in_chunks: Array[PackedInt32Array] = []
	measures_in_chunks.resize(job.chunk_count)
	# For phrases, keys will be the starting measure number
	var phrase_lengths: Dictionary[int,int] = {}
	var phrase_note_indices: Dictionary[int,PackedInt32Array] = {}
	var phrase_note_counts: Dictionary[int,int] = {}
	var phrase_marker_positions: Dictionary[int,Vector2] = {}
	var phrase_activation_lengths: Dictionary[int,int] = {}
	var phrase_next_measures: Dictionary[int,int] = {}

	# First pass: gather measure note counts and chunk info
	for m in notes_in_measure.keys():
		assert(!notes_in_measure[m].is_empty(), "Empty measure found in notes_in_measure!")
		measure_note_counts[m] = notes_in_measure[m].size()
		var chunk_idx: int = m / SynRoadSongManager.CHUNK_LENGTH_IN_MEASURES
		if not measures_in_chunks[chunk_idx]:
			measures_in_chunks[chunk_idx] = PackedInt32Array()
		measures_in_chunks[chunk_idx].append(m)
	result.measure_note_counts = measure_note_counts
	result.measures_in_chunks = measures_in_chunks
	
	# Second pass: build phrases
	for m in notes_in_measure.keys():
		if job.suppressed_measures[m]:
			continue
		phrase_note_indices[m] = PackedInt32Array()
		var first_note = notes_in_measure[m][0]
		var lane: int = note_map[sorted_beats[first_note]]
		var x_pos: float = (lane - 1) * LANE_GAP
		var z_pos: float = (sorted_beats[first_note] * job.length_per_beat)
		phrase_marker_positions[m] = Vector2(x_pos, z_pos)
		phrase_note_indices[m].append_array(notes_in_measure[m])
		if notes_in_measure.has(m + 1) and not job.suppressed_measures[m + 1]:
			phrase_lengths[m] = 2
			phrase_note_indices[m].append_array(notes_in_measure[m + 1])
		else:
			phrase_lengths[m] = 1
		phrase_note_counts[m] = phrase_note_indices[m].size()
		phrase_note_indices.sort()
		var activation_length = job.track_reset
		var target_measure = m + (phrase_lengths[m] - 1) + activation_length
		for i in range(target_measure, m, -1):
			if i < job.total_measures and job.suppressed_measures[i]:
				target_measure += 1
				activation_length += 1
		phrase_activation_lengths[m] = min(job.track_reset, (job.total_measures - (m + phrase_lengths[m])))
		if target_measure >= job.total_measures:
			phrase_next_measures[m] = job.total_measures
		elif measure_note_counts.keys().has(target_measure):
			phrase_next_measures[m] = target_measure
		else:
			# Find the next available measure with notes after target_measure
			var next_measure = target_measure + 1
			while next_measure < job.total_measures:
				if measure_note_counts.keys().has(next_measure):
					phrase_next_measures[m] = next_measure
					break
				next_measure += 1
			if next_measure >= job.total_measures:
				phrase_next_measures[m] = job.total_measures
		
	result.phrase_starts = PackedInt32Array(phrase_lengths.keys())
	result.phrase_lengths = PackedInt32Array(phrase_lengths.values())
	result.phrase_note_indices = phrase_note_indices.values()
	result.phrase_note_counts = PackedInt32Array(phrase_note_counts.values())
	result.phrase_marker_positions = PackedVector2Array(phrase_marker_positions.values())
	result.phrase_activation_lengths = PackedInt32Array(phrase_activation_lengths.values())
	result.phrase_next_measures = PackedInt32Array(phrase_next_measures.values())

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
