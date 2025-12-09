class_name SynRoadCatalogPreprocessor

var thread: Thread
var mutex := Mutex.new()
var pending_jobs: Array = []
var completed: Array = []
var running := false

func queue_job(song_resource_path: String):
	mutex.lock()
	pending_jobs.append(song_resource_path)
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
			"song_resource_path": job,
			"result": result,
		})
		mutex.unlock()
	mutex.lock()
	running = false
	mutex.unlock()
	return

func take_completed():
	mutex.lock()
	var out = completed.duplicate()
	print("Taking %d completed preprocessor results" % out.size())
	completed.clear()
	mutex.unlock()
	return out

func wait_for_all():
	if thread:
		thread.wait_to_finish()
	running = false

func _process_job(song_resource_path: String) -> Dictionary:
	print("Preprocessing song: %s" % song_resource_path)
	var result: Dictionary = {}
	var song_data = ResourceLoader.load(song_resource_path) as SongData
	if not song_data:
		result["success"] = false
		result["error_message"] = "Failed to load song data."
		print("Failed to load song data for: %s" % song_resource_path)
		return result
	
	# Load MIDI data if not already loaded
	if not song_data._midi_data:
		song_data._load_midi_data()
	
	var midi_data = song_data._midi_data
	if not midi_data:
		result["success"] = false
		result["error_message"] = "MIDI data is missing."
		print("MIDI data missing for: %s" % song_resource_path)
		return result
	
	print("  Loaded MIDI data, tracks: %d, ticks_per_beat: %d" % [midi_data.tracks.size(), song_data.ticks_per_beat])
	
	result["bpm"] = song_data.bpm

	var diff_data := {}
	for diff in [96, 102, 108, 114]:
		diff_data[diff] = {"note_count": 0, "beat_positions": []}
	
	# Scan all tracks once, accumulating notes for each difficulty
	for track in song_data.tracks:
		var track_idx = song_data.track_names.find(track.midi_track_name)
		if track_idx < 0:
			print("  Track '%s' not found in MIDI" % track.midi_track_name)
			continue
		
		print("  Scanning track %d: %s" % [track_idx, track.midi_track_name])
		var tick := 0
		for event in midi_data.tracks[track_idx].events:
			tick += event.delta_time
			if event is MidiData.NoteOn and event.velocity > 0:
				var beat_pos = float(tick) / float(song_data.ticks_per_beat)

				for diff in [96, 102, 108, 114]:
					if event.note == diff or event.note == diff + 2 or event.note == diff + 4:
						diff_data[diff].note_count += 1
						diff_data[diff].beat_positions.append(beat_pos)
						break
	
	# Calculate densities and build result
	for diff in [96, 102, 108, 114]:
		var note_count = diff_data[diff].note_count
		var beat_positions = diff_data[diff].beat_positions
		if note_count > 0:
			var density = _calculate_average_density(beat_positions, song_data.lead_in_measures, song_data.playable_measures)
			density /= song_data.tracks.size()  # Normalize by number of tracks
			var rating = calculate_difficulty_rating(density, song_data.bpm)
			match diff:
				108:
					rating += 0.5  # Slight bump for Hard
				114:
					rating += 1.0  # Bigger bump for Expert
			if not result.has("difficulties"):
				result["difficulties"] = {}
			result["difficulties"][diff] = {
				"note_count": note_count,
				"average_density": density,
				"difficulty_rating": clampi(rating, 1, 10),
			}
	
	print("  Found difficulties: %s" % str(result.get("difficulties", {}).keys()))
	result["success"] = true

	return result

func _calculate_average_density(beat_positions: Array, lead_in_measures: int, playable_measures: int) -> float:
	if beat_positions.size() == 0:
		return -1.0
	
	var num_phrases = playable_measures - 1
	if num_phrases <= 0:
		return 0.0
	
	# Sort beat positions once
	var sorted_beats = beat_positions.duplicate()
	sorted_beats.sort()
	
	var phrase_note_sum := 0
	var beat_idx := 0
	var total_measures = playable_measures + lead_in_measures
	
	# For each phrase (2-measure window)
	for i in range(lead_in_measures, total_measures - 1):
		var phrase_start := float(i * 4)
		var phrase_end := float((i + 2) * 4)
		
		# Skip beats before this phrase
		while beat_idx < sorted_beats.size() and sorted_beats[beat_idx] < phrase_start:
			beat_idx += 1
		
		# Count beats in this phrase
		var count := 0
		var temp_idx := beat_idx
		while temp_idx < sorted_beats.size() and sorted_beats[temp_idx] < phrase_end:
			count += 1
			temp_idx += 1
		
		phrase_note_sum += count
	
	return float(phrase_note_sum) / float(num_phrases)

func calculate_difficulty_rating(density: float, bpm: float) -> float:
	var notes_per_minute = density * (bpm / (60.0 * 4.0))
	# Adjusted logarithmic scale with better distribution
	var score = log(notes_per_minute + 1) * 3.34 + 0.75
	return score
