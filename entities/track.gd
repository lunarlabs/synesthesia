class_name SynRoadTrack
extends Node3D

#TODO: fix the color assignments, don't make them fullbright (keep ps4/CroCru or use ps2 theme??)
static var INSTRUMENTS = [
	["Drums", Color(0.8, 0, 1), "uid://bx04vawou1p2o", "uid://w401c706l7dq"],
	["Bass", Color(0.129, 0.25, 1), "uid://dmfgawpqalfv3", "uid://b7mxrnn681i7t"],
	["Guitar", Color(1, 0, 0), "uid://bihm6tbkft235", "uid://5qhhjlqiksto"],
	["Synth", Color(1, .8, 0), "uid://d01i5nlpc34dy", "uid://dtebx5wg367bw"],
	["Vocals", Color(0, 1, 0.2), "uid://bdeui16xuol6", "uid://5vj1puwyti0d"],
	["FX", Color(0, .9, 1), "uid://dym0vwrypvoco", "uid://bpjy82igjyw2q"],
]
const MISBLAST_SCENE: PackedScene = preload("res://entities/misblast.tscn")
const BLASTING_VOLUME = -3.0
const UNFOCUSED_VOLUME = -7.0
const MUTED_VOLUME = -80.0
const CHUNK_LOAD_RANGE_FORWARD = 3
const CHUNK_UNLOAD_RANGE_BEHIND = 2
const STANDARD_LENGTH_PER_BEAT = 4.0
const BEATS_PER_MEASURE = 4.0
var song_node: SynRoadSong
var conductor
var track_index: int = -1
var track_data: GameplayTrackData
var lane_tint: Color
var audio_file: String
var instrument: int
var instrument_note_material: StandardMaterial3D
var instrument_ghost_material: StandardMaterial3D
var length_per_beat: float = STANDARD_LENGTH_PER_BEAT
var note_nodes: Array[SynRoadNote] = []
var measure_nodes: Array[Node3D]
var chunks: Array[Node3D] = []
var furthest_chunk_loaded := -1
var reset_measure: int = 0
var marker_measure_index: int = 0
var current_phrase_index: int = 0
var phrase_notes_blasted: int = 0
var blasting_phrase: bool = false
var next_note_idx_per_lane: Array[int] = [0, 0, 0, ] # Track which note we're processing next in each lane
var next_note_idx := 0 # Track which note we're processing next in autoblast
var _active_track := false
var is_active: bool:
	get: return _active_track

var phrase_score_value: int:
	get:
		if current_phrase_index < track_data.phrase_note_counts.size():
			return track_data.phrase_note_counts[current_phrase_index]
		return 0

var phrase_start_measure: int:
	get:
		if current_phrase_index < track_data.phrase_starts.size():
			return track_data.phrase_starts[current_phrase_index]
		return 0

@onready var asp = $Music as AudioStreamPlayer
@onready var miss_sound = $MissSound as AudioStreamPlayer
@onready var marker = $Marker as Node3D
@onready var pfx = $Whoosh as GPUParticles3D
var rails: MultiMeshInstance3D
var vol_dB: float:
	get:
		return asp.volume_db

signal started_phrase(phrase_score_value: int, start_measure: int, measure_count: int)
signal track_activated(phrase_score_value: int, start_measure: int)
signal streak_broken
signal inactive_phrase_missed()
signal active_phrase_missed
signal note_hit(timing: float)

func _enter_tree():
	rails = get_node("MultiMesh") as MultiMeshInstance3D
	lane_tint = INSTRUMENTS[instrument][1] as Color
	instrument_note_material = load(INSTRUMENTS[instrument][2]) as StandardMaterial3D
	instrument_ghost_material = load(INSTRUMENTS[instrument][3]) as StandardMaterial3D
	rails.material_override = instrument_ghost_material
	song_node = get_parent() as SynRoadSong
	conductor = song_node.get_node("Conductor")
	print("track %d instantiating rails" % track_index)
	rails.multimesh.instance_count = song_node.total_measures * 2
	length_per_beat = song_node.length_per_beat
	chunks.resize(song_node.manager_node.chunk_count)
	measure_nodes.resize(song_node.total_measures)
	note_nodes.resize(track_data.note_map.keys().size())
	for i in range(song_node.total_measures * 2):
		var rail_transform = Transform3D.IDENTITY
		@warning_ignore("integer_division")
		var z_pos = - (BEATS_PER_MEASURE * length_per_beat) * (int(i / 2) + 0.5)
		var x_pos = 1.17 if i % 2 == 0 else -1.17
		rail_transform.origin = Vector3(x_pos, -0.25, z_pos)
		var scale_z = length_per_beat / STANDARD_LENGTH_PER_BEAT
		rail_transform.basis = rail_transform.basis.scaled(Vector3(1.0, 1.0, scale_z))
		rails.multimesh.set_instance_transform(i, rail_transform)

func _ready():
	asp.stream = load(audio_file) as AudioStream
	# Cache materials once at track level instead of loading in each chunk
	asp.volume_db = UNFOCUSED_VOLUME
	asp.add_to_group("AudioPlayers")
	asp.add_to_group("TrackAudio")
	pfx.process_material.color = lane_tint
	marker.position.x = track_data.phrase_marker_positions[0].x
	marker.position.z = track_data.phrase_marker_positions[0].y
	song_node._update_track_marker_cache(track_index, track_data.phrase_starts[0])
	song_node._update_track_reset_cache(track_index, track_data.phrase_starts[0])
	reset_measure = track_data.phrase_starts[0]
	marker.visible = song_node.manager_node.hide_streak_hints == false

@warning_ignore("unused_parameter")
func _process(delta: float):
	var current_time = conductor.time_elapsed
	marker.position.y = lerp(1.2, 1.7, fmod(conductor.current_beat, 1))

	if song_node.lead_in_measures >= 0 or song_node.finished:
		return
	if not song_node.manager_node.autoblast:
		_process_manual(current_time)
	else:
		_process_autoblast(current_time)

func _process_manual(current_time: float):
	for lane_index in range(3):
		var lane_notes = track_data.lane_notes[lane_index]
		var next_lane_note_idx = next_note_idx_per_lane[lane_index]
		if next_lane_note_idx >= lane_notes.size():
			continue
		var note_idx = lane_notes[next_lane_note_idx]
		var note_time = _get_note_time(note_idx)
		if conductor.current_measure < reset_measure and current_time > note_time:
			# Track hasn't been reset yet, but we've passed the note. Just advance the index.
			next_note_idx_per_lane[lane_index] += 1
		elif (!is_active) and current_time > note_time:
			# Track is not active, but we've passed the note. Mark as missed and mute the track.
			next_note_idx_per_lane[lane_index] += 1
			if asp.volume_db != MUTED_VOLUME:
				asp.volume_db = MUTED_VOLUME
			# TODO: See if the passed note was the first note in the phrase
			# and signal inactive_phrase_missed if it was
			if current_phrase_index < track_data.phrase_starts.size() \
			and note_idx >= track_data.phrase_note_indices[current_phrase_index][0]:
				_advance_phrase()
				inactive_phrase_missed.emit()

		elif is_active and current_time > note_time + song_node.manager_node.miss_window:
			# We're past the hit window, should be a miss but check if it was already blasted
			var note_node = note_nodes[note_idx] as SynRoadNote
			next_note_idx_per_lane[lane_index] += 1
			if note_node and note_node.blasted:
				# Blasted but the index didn't advance. We're done.
				continue
			if asp.volume_db != MUTED_VOLUME:
				asp.volume_db = MUTED_VOLUME
			if current_phrase_index < track_data.phrase_note_indices.size() \
			and note_idx in track_data.phrase_note_indices[current_phrase_index]:
				active_phrase_missed.emit()
				streak_broken.emit()
				_advance_phrase()

func _process_autoblast(current_time: float):
	if is_active:
		# Process notes in time order
		while next_note_idx < track_data.note_times.size():
			var note_time = track_data.note_times[next_note_idx]
			
			# If the note is in the future, we're done for now
			if note_time > current_time:
				break
				
			# Process current note
			var note_idx = next_note_idx
			
			# Check if note is part of current active phrase and blast if so
			if current_phrase_index < track_data.phrase_note_indices.size():
				if note_idx in track_data.phrase_note_indices[current_phrase_index]:
					var note_node = note_nodes[note_idx] as SynRoadNote
					if !note_node.blasted:
						var lane = track_data.note_map.values()[note_idx]
						song_node._targets[lane].flash()
						note_node.blast(true)
						note_hit.emit(0.0) # perfect timing
						asp.volume_db = BLASTING_VOLUME
						phrase_notes_blasted += 1
						
						# Start phrase logic
						if !blasting_phrase:
							started_phrase.emit(
								track_data.phrase_note_counts[current_phrase_index],
								track_data.phrase_starts[current_phrase_index],
								track_data.phrase_lengths[current_phrase_index]
							)
							blasting_phrase = true
							print("Track %d started phrase %d (blasted note idx %d)" % [track_index, current_phrase_index, note_idx])
							marker.hide()
			
			next_note_idx += 1
			
		# Check for phrase completion
		if blasting_phrase and current_phrase_index < track_data.phrase_note_counts.size():
			if phrase_notes_blasted >= track_data.phrase_note_counts[current_phrase_index]:
				print("Track %d completed phrase %d (notes: %d/%d)" % [track_index, current_phrase_index, phrase_notes_blasted, track_data.phrase_note_counts[current_phrase_index]])
				activate(current_phrase_index)
				phrase_notes_blasted = 0
				blasting_phrase = false
	else:
		# Inactive track in autoblast mode: check if we've passed the phrase start
		if conductor.current_measure >= reset_measure and current_phrase_index < track_data.phrase_starts.size():
			var phrase_start_beat = (track_data.phrase_starts[current_phrase_index] - 1) * length_per_beat
			
			# If we've passed the phrase start, we missed it - mute the track
			if conductor.current_beat > phrase_start_beat + song_node.manager_node.miss_window / song_node.seconds_per_beat:
				if asp.volume_db != MUTED_VOLUME:
					asp.volume_db = MUTED_VOLUME

func try_blast(lane_index: int, specific_time: float = -1.0):
	var current_time = specific_time if specific_time >= 0.0 else conductor.time_elapsed
	var lane_note_index = next_note_idx_per_lane[lane_index]
	if conductor.current_measure >= reset_measure - 1:
		if lane_note_index >= track_data.lane_notes[lane_index].size():
			_misblast(conductor.current_beat, lane_index)
			if blasting_phrase:
				phrase_notes_blasted = 0
				asp.volume_db = MUTED_VOLUME
				blasting_phrase = false
				active_phrase_missed.emit()
				streak_broken.emit()
				_advance_phrase()
			return
		var target_note_index = track_data.lane_notes[lane_index][lane_note_index]
		var target_note_time = _get_note_time(target_note_index)
		var time_offset = (target_note_time - current_time)
		if abs(time_offset) <= song_node.manager_node.hit_window:
			var note_node = note_nodes[target_note_index] as SynRoadNote
			if note_node.blasted:
				return # Don't double-blast
			next_note_idx_per_lane[lane_index] += 1
			note_node.blast(true)
			note_hit.emit(time_offset)
			asp.volume_db = BLASTING_VOLUME
			if current_phrase_index >= track_data.phrase_note_indices.size():
				return
			if target_note_index == track_data.phrase_note_indices[current_phrase_index][phrase_notes_blasted]:
				phrase_notes_blasted += 1
				if !blasting_phrase:
					started_phrase.emit(
						track_data.phrase_note_counts[current_phrase_index],
						track_data.phrase_starts[current_phrase_index],
						track_data.phrase_lengths[current_phrase_index]
					)
					blasting_phrase = true
					marker.hide()
				if phrase_notes_blasted >= track_data.phrase_note_counts[current_phrase_index]:
					activate(current_phrase_index)
					phrase_notes_blasted = 0
					blasting_phrase = false
					marker.visible = song_node.manager_node.hide_streak_hints == false
		elif conductor.current_measure >= reset_measure:
			_misblast(conductor.current_beat, lane_index)
			if blasting_phrase:
				phrase_notes_blasted = 0
				asp.volume_db = MUTED_VOLUME
				blasting_phrase = false
				active_phrase_missed.emit()
				streak_broken.emit()
				_advance_phrase()
			
		
	# # Allow a slight early hit on the first post-reset note (reset_countdown == 1) if within window and early (time_offset > 0)
	# if abs(time_offset) <= song_node.manager_node.hit_window and (reset_countdown == 0 or (reset_countdown == 1 and time_offset > 0)):
	# 	var note_node = note_nodes[target_note] as SynRoadNote
	# 	if note_node.blasted:
	# 		return # Don't double-blast
	# 	note_node.blast(true)
	# 	note_hit.emit(time_offset)
	# 	#print("  Track %s: Blasted note at beat %.2f (offset %.3f)" % [midi_name, target_note, time_offset])
	# 	if phrase_notes_dict.has(note_node):
	# 		if !blasting_phrase:
	# 			# preprocessed phrase measure count
	# 			var phrase_measure_count = preprocessed_phrases[current_phrase_index].measure_count
	# 			started_phrase.emit(phrase_score_value, phrase_start_measure, phrase_measure_count)
	# 			blasting_phrase = true
	# 			marker.hide()
	# 		phrase_notes.erase(note_node)
	# 		phrase_notes_count -= 1  # Keep in sync with phrase_notes array
	# 		phrase_notes_dict.erase(note_node)
	# 		if phrase_notes_count == 0:
	# 			activate(floori(target_note / BEATS_PER_MEASURE) + 1)
	# 			blasting_phrase = false
	# 	asp.volume_db = BLASTING_VOLUME
	# 	next_note_idx_per_lane[lane_index] += 1
	# else:
	# 	miss_sound.play()
	# 	_spawn_misblast_effect(current_beat, lane_index)
	# 	if blasting_phrase:
	# 		asp.volume_db = MUTED_VOLUME
	# 		blasting_phrase = false
	# 		active_phrase_missed.emit()
	# 		print("Track %s breaking streak for misblast at beat %.2f (measure %d)" % 
	# 			[midi_name, current_beat, song_node.current_measure()])
	# 		streak_broken.emit()
	# 		if reset_countdown == 0:
	# 			_process_phrase_at_measure(song_node.current_measure() + 1)

func _advance_phrase():
	if current_phrase_index >= 0:
		# unmark previous phrase
		for i in range(track_data.phrase_lengths[current_phrase_index]):
			var measure = track_data.phrase_starts[current_phrase_index] + i
			var cube = measure_nodes[measure].get_node("track_geometry").get_node("Cube")
			cube.set_instance_shader_parameter("phrase", false)
		for i in track_data.phrase_note_indices[current_phrase_index]:
			var note = note_nodes[i]
			note.set_phrase_note(false)
	phrase_notes_blasted = 0
	if current_phrase_index >= track_data.phrase_starts.size():
		# no more phrases
		move_marker(-1)
		return

	while (
	current_phrase_index < track_data.phrase_starts.size()
	and (conductor.current_measure > track_data.phrase_starts[current_phrase_index]
	or track_data.phrase_starts[current_phrase_index] < reset_measure)
	):
		# if we're past the measure the phrase starts on, keep going forward
		current_phrase_index += 1

	if current_phrase_index >= track_data.phrase_starts.size():
		move_marker(-1)
		return

	var first_note_index = track_data.phrase_note_indices[current_phrase_index][0]
	if conductor.time_elapsed > track_data.note_times[first_note_index]:
		# if we've passed the first note in the measure, move to next.
		current_phrase_index += 1

	if current_phrase_index >= track_data.phrase_starts.size():
		# Let's do the bounds check again!
		move_marker(-1)
		return


	if marker_measure_index != -1 and marker_measure_index < current_phrase_index:
		marker_measure_index = current_phrase_index
		move_marker(marker_measure_index)

	for i in range(track_data.phrase_lengths[current_phrase_index]):
		var measure = track_data.phrase_starts[current_phrase_index] + i
		var measure_node = measure_nodes[measure]
		if measure_node:
			var cube = measure_node.get_node("track_geometry").get_node("Cube")
			cube.set_instance_shader_parameter("phrase", true)
	for i in track_data.phrase_note_indices[current_phrase_index]:
		var note = note_nodes[i]
		if note and is_active:
			note.set_phrase_note(true)

func get_measure_index_after(measure_num: int) -> int:
	for i in range(current_phrase_index, track_data.phrase_starts.size()):
		if track_data.phrase_starts[i] > measure_num:
			return i
	return -1

func get_note_count_in_measure(measure_num: int) -> int:
	if track_data.measure_note_counts.has(measure_num):
		return track_data.measure_note_counts[measure_num]
	return 0

func move_marker(measure_index: int):
	if measure_index < 0 or measure_index >= track_data.phrase_marker_positions.size():
		song_node._update_track_marker_cache(track_index, -1)
		marker.hide()
		return
	marker.position.x = track_data.phrase_marker_positions[measure_index].x
	marker.position.z = track_data.phrase_marker_positions[measure_index].y
	marker_measure_index = measure_index
	# tell the song node to update its marker cache with the actual measure number
	song_node._update_track_marker_cache(track_index, track_data.phrase_starts[marker_measure_index])

func set_active(active: bool):
	_active_track = active
	rails.visible = active
	if current_phrase_index < track_data.phrase_starts.size():
		for i in track_data.phrase_note_indices[current_phrase_index]:
			var note = note_nodes[i]
			if note:
				note.set_phrase_note(active)
	if !active:
		marker.visible = song_node.manager_node.hide_streak_hints == false
		if blasting_phrase:
			blasting_phrase = false
			phrase_notes_blasted = 0
			print("  Track %d: Deactivating while blasting phrase, breaking streak" % track_index)
			active_phrase_missed.emit()
			streak_broken.emit()
			_advance_phrase()
	if not active and asp.volume_db != MUTED_VOLUME:
		asp.volume_db = UNFOCUSED_VOLUME
	# When becoming active, update to the current phrase if not in reset countdown
	if active:
		_advance_phrase()
		if song_node.manager_node.autoblast:
			_sync_autoblast_state()

func _sync_autoblast_state():
	var current_time = conductor.time_elapsed
	while next_note_idx < track_data.note_times.size() and track_data.note_times[next_note_idx] < current_time:
		next_note_idx += 1
	print("Track %d synced autoblast state. Next note idx: %d, Time: %.2f" % [track_index, next_note_idx, current_time])
func _get_note_time(note_index: int) -> float:
	return track_data.note_times[note_index]

func _get_note_lane(note_index: int):
	var beat = track_data.note_map.keys()[note_index]
	return track_data.note_map[beat]

func _on_song_new_measure(_measure_num: int):
	if _measure_num < song_node.manager_node.measure_in_chunks.size():
		var current_chunk = song_node.manager_node.measure_in_chunks[_measure_num]
	#	print ("We are on chunk %d" % current_chunk)
		var target_ahead = current_chunk + CHUNK_LOAD_RANGE_FORWARD
		var target_behind = current_chunk - CHUNK_UNLOAD_RANGE_BEHIND
		if furthest_chunk_loaded < target_ahead and target_ahead < song_node.manager_node.chunk_count:
			request_chunks(target_ahead)
		if target_behind >= 0 and chunks[target_behind]:
			print("Track %d recycling chunk %d" % [track_index, target_behind])
			ChunkManager.recycle_chunk(chunks[target_behind])
			chunks[target_behind] = null

func request_chunks(furthest: int):
	while furthest_chunk_loaded < furthest:
		furthest_chunk_loaded += 1
		ChunkManager.request_chunk(track_index, furthest_chunk_loaded)

func activate(phrase_idx: int):
	print("  Track %d: Activating phrase at measure %d" % [track_index, track_data.phrase_starts[phrase_idx]])
	var phrase_end_measure = track_data.phrase_starts[phrase_idx] + track_data.phrase_lengths[phrase_idx] - 1
	reset_measure = track_data.phrase_next_measures[phrase_idx]
	blasting_phrase = false
	asp.volume_db = UNFOCUSED_VOLUME
	track_activated.emit(
		track_data.phrase_note_counts[phrase_idx],
		phrase_end_measure
	)
	_play_pfx(phrase_end_measure)
	var activation_end_measure = reset_measure if reset_measure != -1 else song_node.total_measures
	for i in range(phrase_end_measure, activation_end_measure):
		if measure_nodes[i]:
			var cube = measure_nodes[i].get_node("track_geometry").get_node("Cube")
			cube.hide()
		if i in track_data.notes_in_measure.keys():
			for j in track_data.notes_in_measure[i]:
				if note_nodes[j]:
					note_nodes[j].blast(false)
	phrase_notes_blasted = 0
	song_node._update_track_reset_cache(track_index, reset_measure)
	_advance_phrase()
	marker.visible = (song_node.manager_node.hide_streak_hints == false) and reset_measure != -1

func _play_pfx(start_measure: int):
	pfx.position.z = start_measure * - (BEATS_PER_MEASURE * length_per_beat)
	pfx.emitting = true

func current_measure_is_unactivated() -> bool:
	return conductor.current_measure >= reset_measure and conductor.current_measure in track_data.phrase_starts

func _misblast(beat_position: float, lane_index: int):
	miss_sound.play()
	asp.volume_db = MUTED_VOLUME
	var misblast = MISBLAST_SCENE.instantiate() as Node3D
	misblast.position.z = - (beat_position * length_per_beat)
	misblast.position.x = (lane_index - 1) * 0.6
	add_child(misblast)

class GameplayTrackData:
	## A map of the notes on the track. The key is its beat, the value is its lane.
	var note_map: Dictionary[float, int] = {}
	## An array of the note's times, in seconds.
	var note_times: PackedFloat32Array = []
	## An array of the note node positions in 3D space. The Y-value corresponds to Z-position in world-space
	var note_positions: PackedVector2Array = [] # Y-value here is Z-position in world space
	var lane_notes: Array = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	var notes_in_measure: Dictionary[int, PackedInt32Array] = {}
	var measure_note_counts: Dictionary[int, int] = {}
	var measures_in_chunks: Array[PackedInt32Array] = []
	# For phrases, keys will be the starting measure number
	## An index of phrase starting measures.
	var phrase_starts: PackedInt32Array = []
	## Lengths of phrases, in measures.
	var phrase_lengths: PackedInt32Array = []
	## The note indices in a phrase
	var phrase_note_indices: Array[PackedInt32Array] = []
	var phrase_note_counts: PackedInt32Array = []
	var phrase_marker_positions: PackedVector2Array = []
	var phrase_activation_lengths: PackedInt32Array = []
	var phrase_next_measures: PackedInt32Array = []
