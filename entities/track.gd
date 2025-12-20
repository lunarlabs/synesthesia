class_name SynRoadTrack
extends Node3D

#TODO: fix the color assignments, don't make them fullbright (keep ps4/CroCru or use ps2 theme??)
static var INSTRUMENTS = [
	["Drums", Color(0.8,0,1), "uid://bx04vawou1p2o", "uid://w401c706l7dq"],
	["Bass", Color(0.129,0.25,1), "uid://dmfgawpqalfv3", "uid://b7mxrnn681i7t"],
	["Guitar", Color(1,0,0), "uid://bihm6tbkft235", "uid://5qhhjlqiksto"],
	["Synth", Color(1,.8,0), "uid://d01i5nlpc34dy", "uid://dtebx5wg367bw"],
	["Vocals", Color(0,1,0.2), "uid://bdeui16xuol6", "uid://5vj1puwyti0d"],
	["FX", Color(0,.9,1), "uid://dym0vwrypvoco", "uid://bpjy82igjyw2q"],
]
const MEASURE_SCENE = preload("res://entities/measure.tscn")
const NOTE_SCENE = preload("res://entities/note.tscn")
const MISBLAST_SCENE:PackedScene = preload("res://entities/misblast.tscn")
const RAIL_SCENE = preload("res://entities/rails.tscn")
const BLASTING_VOLUME = -3.0
const UNFOCUSED_VOLUME = -7.0
const MUTED_VOLUME = -80.0
const HIT_BEAT_WINDOW = 0.08
const MISS_BEAT_WINDOW = 0.1
const AUTOBLAST_TIMING_MULTIPLIER = 0.67
const CHUNK_SIZE_MEASURES = 8
const CHUNK_LOAD_RANGE_FORWARD = 3
const CHUNK_UNLOAD_RANGE_BEHIND = 2
const NOTE_VISIBILITY_RANGE_BEATS = 64.0
const STANDARD_LENGTH_PER_BEAT = 4.0
const BEATS_PER_MEASURE = 4.0
var track_data: GameplayTrackData
var lane_tint: Color
var midi_name: String
var audio_file: String
var instrument: int
var instrument_note_material: StandardMaterial3D
var instrument_ghost_material: StandardMaterial3D
var length_multiplier: float = 1.0
var length_per_beat: float = STANDARD_LENGTH_PER_BEAT
var note_map: Dictionary[float, int]
var note_nodes: Array[SynRoadNote] = []
var measure_nodes: Array[Node3D]
var measure_count: int = 0
var chunks: Array[Node3D] = []
var reset_measure: int = 0
var phrase_start_measure:int = 0
var marker_measure:int = 0
var phrase_notes: Array[SynRoadNote]
var phrase_notes_dict: Dictionary[SynRoadNote, bool]  # O(1) lookup instead of Array.has()
var phrase_notes_count: int = 0  # Track count separately to avoid .size() calls. Synced in _process_phrase_at_index(), decremented when notes removed.
var phrase_beats: Array[float]
var phrase_beat_index: int = 0  # Track which beat we're processing next in autoblast
var phrase_score_value:int = 0
var phrase_first_beat: float = 0.0
var beats_in_measure: Dictionary  # Cache beats per measure: int -> Array[float]
var blasting_phrase: bool = false
var lane_note_beats = [[],[],[],]
var next_note_idx_per_lane: Array[int] = [0,0,0,]
var activation_length_measures = 13
var reset_countdown: int = 0
var _active_track := false
var is_active: bool:
	get: return _active_track
var just_activated: bool = false
var preprocessed_phrases: Array[Dictionary]
var current_phrase_index: int = -1

@onready var asp = $Music as AudioStreamPlayer
@onready var miss_sound = $MissSound as AudioStreamPlayer
@onready var marker = $Marker as Node3D
var song_node
var vol_dB: float:
	get:
		return asp.volume_db

signal started_phrase(phrase_score_value:int, start_measure:int, measure_count:int)
signal track_activated(phrase_score_value:int, start_measure:int)
signal streak_broken
signal inactive_phrase_missed(track_name:String)
signal active_phrase_missed
signal note_hit(timing:float)

@onready var rails = $RailMaster

func _enter_tree():
	lane_tint = INSTRUMENTS[instrument][1] as Color
	instrument_note_material = load(INSTRUMENTS[instrument][2]) as StandardMaterial3D
	instrument_ghost_material = load(INSTRUMENTS[instrument][3]) as StandardMaterial3D
	song_node = get_parent() as SynRoadSong
	length_per_beat = song_node.length_per_beat
	chunks.resize(song_node.manager_node.chunk_count)
	measure_nodes.resize(song_node.total_measures)
	note_nodes.resize(track_data.note_map.keys().size())
	for i in range(song_node.total_measures):
		var new_rail = RAIL_SCENE.instantiate() as Node3D
		new_rail.position.z = -(BEATS_PER_MEASURE * length_per_beat) * i
		new_rail.scale.z = length_per_beat / STANDARD_LENGTH_PER_BEAT
		new_rail.mat = instrument_ghost_material
		rails.add_child(new_rail)

func _ready():
	asp.stream = load(audio_file) as AudioStream
	# Cache materials once at track level instead of loading in each chunk
	asp.volume_db = UNFOCUSED_VOLUME
	asp.add_to_group("AudioPlayers")
	asp.add_to_group("TrackAudio")
	reset_measure = track_data.notes_in_measure.keys()[0]
	phrase_start_measure = reset_measure
	marker.visible = song_node.manager_node.hide_streak_hints == false

#func _populateChunks():
#	var chunk_count = ceili(float(beats_in_measure.keys().max() + 1) / CHUNK_SIZE_MEASURES)
#	for i in chunk_count:
#		#print("populating chunk %d" % i)
#		chunks.append(MeasureChunk.new(i * CHUNK_SIZE_MEASURES, self))

func try_blast(lane_index:int):
	var current_beat = song_node.current_beat()
	var note_index = next_note_idx_per_lane[lane_index]
	if note_index >= lane_note_beats[lane_index].size():
		# No notes in this lane or all notes passed - still show misblast
		miss_sound.play()
		_spawn_misblast_effect(current_beat, lane_index)
		# Break streak if blasting a phrase
		if blasting_phrase:
			asp.volume_db = MUTED_VOLUME
			blasting_phrase = false
			active_phrase_missed.emit()
			print("Track %s breaking streak for misblast (no notes in lane) at beat %.2f (measure %d)" % 
				[midi_name, current_beat, song_node.current_measure()])
			streak_broken.emit()
			if reset_countdown == 0:
				_process_phrase_at_measure(song_node.current_measure() + 1)
		return
	var target_note = lane_note_beats[lane_index][note_index]
	var time_offset = (target_note - current_beat) * song_node.seconds_per_beat
	# Allow a slight early hit on the first post-reset note (reset_countdown == 1) if within window and early (time_offset > 0)
	if abs(time_offset) <= HIT_BEAT_WINDOW and (reset_countdown == 0 or (reset_countdown == 1 and time_offset > 0)):
		var note_node = note_nodes[target_note] as SynRoadNote
		if note_node.blasted:
			return # Don't double-blast
		note_node.blast(true)
		note_hit.emit(time_offset)
		#print("  Track %s: Blasted note at beat %.2f (offset %.3f)" % [midi_name, target_note, time_offset])
		if phrase_notes_dict.has(note_node):
			if !blasting_phrase:
				# preprocessed phrase measure count
				var phrase_measure_count = preprocessed_phrases[current_phrase_index].measure_count
				started_phrase.emit(phrase_score_value, phrase_start_measure, phrase_measure_count)
				blasting_phrase = true
				marker.hide()
			phrase_notes.erase(note_node)
			phrase_notes_count -= 1  # Keep in sync with phrase_notes array
			phrase_notes_dict.erase(note_node)
			if phrase_notes_count == 0:
				activate(floori(target_note / BEATS_PER_MEASURE) + 1)
				blasting_phrase = false
		asp.volume_db = BLASTING_VOLUME
		next_note_idx_per_lane[lane_index] += 1
	else:
		miss_sound.play()
		_spawn_misblast_effect(current_beat, lane_index)
		if blasting_phrase:
			asp.volume_db = MUTED_VOLUME
			blasting_phrase = false
			active_phrase_missed.emit()
			print("Track %s breaking streak for misblast at beat %.2f (measure %d)" % 
				[midi_name, current_beat, song_node.current_measure()])
			streak_broken.emit()
			if reset_countdown == 0:
				_process_phrase_at_measure(song_node.current_measure() + 1)

func set_active(active: bool):
	_active_track = active
	rails.visible = active
	for note in phrase_notes:
		note.set_phrase_note(active)
	if !active and blasting_phrase:
		blasting_phrase = false
		print("  Track %s: Deactivating while blasting phrase, breaking streak" % midi_name)
		streak_broken.emit()
		_process_phrase_at_measure(song_node.current_measure() + 1)
	if not active and asp.volume_db != MUTED_VOLUME:
		asp.volume_db = UNFOCUSED_VOLUME
	# When becoming active, update to the current phrase if not in reset countdown

func _process(delta: float):
	marker.position.y = lerp(1.2, 1.7, fmod(song_node.current_beat(), 1))
	if song_node.lead_in_measures >= 0 or song_node.finished:
		return
	var current_time = song_node.time_elapsed
	var current_beat = song_node.current_beat()
	var current_measure = song_node.current_measure()
	var miss_beat_window = MISS_BEAT_WINDOW / song_node.seconds_per_beat
	
	# Phrase-level progression based on precomputed first beat
	# Only auto-fail if we've WELL passed the window AND haven't started hitting this phrase
	if reset_countdown == 0 and phrase_first_beat > 0.0 and !blasting_phrase:
		# If we've passed the phrase start beyond the miss window
		if current_beat > (phrase_first_beat + miss_beat_window):
			# We missed the entire phrase window without hitting any notes
			if is_active and current_measure >= phrase_start_measure and !song_node._manager_node.autoblast:
				active_phrase_missed.emit()
				print("Track %s breaking streak for missing phrase at measure %d (phrase_start_measure=%d, current_beat=%.2f, phrase_first_beat=%.2f)" % 
					[midi_name, current_measure, phrase_start_measure, current_beat, phrase_first_beat])
				streak_broken.emit()
			else:
				# Don't penalize for phrases at or past the song's end
				if !phrase_notes_dict.is_empty() and phrase_start_measure < song_node.total_measures and !song_node._manager_node.autoblast:
#					print("Track %s missed inactive phrase starting at measure %d" % [midi_name, phrase_start_measure])
					inactive_phrase_missed.emit(midi_name)
			if marker_measure == phrase_start_measure:	
				_move_marker(get_first_available_measure(current_measure + 1))
			marker.visible = !song_node._manager_node.hide_streak_hints
			
			if asp.volume_db != MUTED_VOLUME:
				asp.volume_db = MUTED_VOLUME
			
			# Advance to next phrase

	if !song_node._manager_node.autoblast:
		# We are not in autoblast mode, just check for missed notes
		for lane_index in range(3):
			var lane_beats = lane_note_beats[lane_index]
			var note_index = next_note_idx_per_lane[lane_index]
			if note_index >= lane_beats.size():
				continue
			var target_beat = lane_beats[note_index]
			var target_time = target_beat * song_node.seconds_per_beat
			if current_time > target_time + MISS_BEAT_WINDOW:
				# Check if note was already blasted before marking as missed
				var note_node = note_nodes.get(target_beat) as SynRoadNote
				if note_node and note_node.blasted:
					# Note was already hit, just advance the index
					next_note_idx_per_lane[lane_index] += 1
					continue
				
				# If we're actively blasting a phrase and this note is part of it, break streak
				if blasting_phrase and note_node and phrase_notes_dict.has(note_node):
					if is_active:
						active_phrase_missed.emit()
						print("Track %s breaking streak for missing note at beat %.2f (measure %d)" % 
							[midi_name, target_beat, song_node.current_measure()])
						streak_broken.emit()
						blasting_phrase = false
						if asp.volume_db != MUTED_VOLUME:
							asp.volume_db = MUTED_VOLUME
						if reset_countdown == 0:
							var next_measure = song_node.current_measure() + 1
							_process_phrase_at_measure(next_measure)
							_move_marker(get_first_available_measure(next_measure))
							marker.visible = !song_node._manager_node.hide_streak_hints
				
				next_note_idx_per_lane[lane_index] += 1
	else:
		if is_active:
			# TIME TO FAKE IT BABY!
			# Optimized: only process beats from current index until we find one that hasn't been reached
			# Since phrase_beats is sorted, we can stop early. Use index instead of removing elements.
			var notes_blasted = 0
			while phrase_beat_index < phrase_beats.size() and phrase_beats[phrase_beat_index] <= current_beat:
				var beat = phrase_beats[phrase_beat_index]
				asp.volume_db = BLASTING_VOLUME
				if !note_nodes[beat].blasted:
					note_nodes[beat].blast(true)
					# Emit note_hit signal with perfect timing (0.0 offset)
					note_hit.emit(0.0)
				# Check if this is the first note of the phrase
				if !blasting_phrase:
					var phrase_measure_count = preprocessed_phrases[current_phrase_index].measure_count
					started_phrase.emit(phrase_score_value, phrase_start_measure, phrase_measure_count)
					print("  Track %s: Starting autoblast phrase at measure %d" % [midi_name, phrase_start_measure])
					blasting_phrase = true
					marker.hide()
					#print("    Blasted beat %.2f" % beat)
					#print("    Remaining phrase beats: %s" % str(phrase_beats))
				phrase_beat_index += 1
				notes_blasted += 1
			
			# Check if phrase is complete
			if phrase_beat_index >= phrase_beats.size() and notes_blasted > 0:
				#print("  Track %s: Phrase complete, activating" % midi_name)
				activate(song_node.current_measure())
				blasting_phrase = false
		else:
			# Inactive track in autoblast mode: check if we've passed the phrase start
			if reset_countdown == 0:
				current_beat = song_node.current_beat()
				var phrase_start_beat = (phrase_start_measure - 1) * length_per_beat
				
				# If we've passed the phrase start, we missed it - mute the track
				if current_beat > phrase_start_beat + MISS_BEAT_WINDOW / song_node.seconds_per_beat:
					if asp.volume_db != MUTED_VOLUME:
						asp.volume_db = MUTED_VOLUME

func _on_song_new_measure(_measure_num: int):
	pass
	

func _process_phrase_at_measure(measure:int):
	# Get the index of the phrase that starts at or after the given measure
	for i in range(preprocessed_phrases.size()):
		if preprocessed_phrases[i].start_measure >= measure:
			current_phrase_index = i
#			_process_phrase_at_index(i)
			return
	# No phrase found at or after the given measure
	phrase_start_measure = song_node.total_measures + 1
	marker_measure = song_node.total_measures + 1
#	print("    No phrase found at or after measure %d" % measure)


func update_marker_for_inactive(after_measure:int):
	# Called by song when another track starts blasting a phrase
	# Position marker at the first phrase starting at or after after_measure
	if is_active:
		return
	
	var new_marker_measure = get_first_available_measure(after_measure)
	
	# Only move forward, never backwards
	if new_marker_measure > marker_measure:
		_move_marker(new_marker_measure)
		if marker_measure <= song_node.total_measures:
			marker.visible = !song_node._manager_node.hide_streak_hints

func activate(start_measure:int):
	reset_countdown = activation_length_measures
	var target_measure = start_measure + activation_length_measures
	var suppressed_measures = song_node._manager_node.suppressed_measures
	
	# Check if target_measure lands in a suppressed range OR if activation spans a checkpoint gap
	var spans_checkpoint = false
	for suppressed in suppressed_measures:
		# Case 1: target_measure itself is suppressed
		if target_measure == suppressed:
			target_measure += 1
			reset_countdown += 1
			print("%s: extending activation due to suppressed measure %d" % [midi_name, suppressed])
			spans_checkpoint = true
		# Case 2: activation window spans the checkpoint (start before, end after)
		elif start_measure < suppressed and target_measure > suppressed:
			reset_countdown += 2
			target_measure += 2
			print("%s: activation spans checkpoint gap at measure %d, extending by 2" % [midi_name, suppressed])
			spans_checkpoint = true
			break  # Only need to handle one checkpoint span per activation
#	print("  Track %s activate: start_measure=%d, activation_length=%d, target_measure=%d" % [midi_name, start_measure, reset_countdown, target_measure])
	_move_marker(get_first_available_measure(target_measure))
	asp.volume_db = UNFOCUSED_VOLUME
	# Save the completed phrase value before finding the next phrase
	var completed_phrase_value = phrase_score_value
	blasting_phrase = false
	just_activated = true
	_process_phrase_at_measure(target_measure)
	# Show marker again after activation
	if phrase_start_measure <= song_node.total_measures:
		marker.visible = !song_node._manager_node.hide_streak_hints
	track_activated.emit(completed_phrase_value, start_measure)

func _catch_up_missed_notes(start_time: float, current_time: float):
	var start_beat = start_time / song_node.seconds_per_beat
	var current_beat = current_time / song_node.seconds_per_beat
	var notes_skipped = 0
	
	for lane_index in range(3):
		while next_note_idx_per_lane[lane_index] < lane_note_beats[lane_index].size():
			var target_beat = lane_note_beats[lane_index][next_note_idx_per_lane[lane_index]]
			if target_beat >= start_beat and target_beat < current_beat:
				# Skip this note
				next_note_idx_per_lane[lane_index] += 1
				notes_skipped += 1
			elif target_beat >= current_beat:
				# Haven't reached this note yet
				break
			else:
				# This note is before the start time (already processed)
				next_note_idx_per_lane[lane_index] += 1
	
	if notes_skipped > 0:
		pass
		#print("  Track %s: skipped %d notes from beat %.2f to %.2f" % 
		#	[midi_name, notes_skipped, start_beat, current_beat])

func _update_note_streaming(measure:int):
#	#print("doing note stream check for measure %d" % measure)
	var chunk_idx = measure / CHUNK_SIZE_MEASURES

	# Bounds checking for unload
#	if chunk_idx - 3 >= 0 and chunk_idx - 3 < chunks.size():
#		chunks[chunk_idx - 3].unload()
	
	# Bounds checking for load
	for offset in range(-1, CHUNK_LOAD_RANGE_FORWARD):
		var target_idx = chunk_idx + offset
#		if target_idx >= 0 and target_idx < chunks.size():
#			chunks[target_idx].load_if_needed()
	
func get_first_available_measure(start_measure:int) -> int:
	for m in range(start_measure, song_node.total_measures + 1):
		if beats_in_measure.has(m) and beats_in_measure[m].size() > 0:
			return m
	return song_node.total_measures + 1

func _move_marker(measure: int):
	marker_measure = measure
	var beat_position = -1.0
	if beats_in_measure.has(measure):
		var beats = beats_in_measure[measure]
		if beats.size() > 0:
			beat_position = beats.min()
	var z_pos = - (beat_position * length_per_beat)
	if note_map.has(beat_position):
		var lane = note_map[beat_position]
		marker.position.x = (lane - 1) * 0.6
	#print("    _move_marker: beat=%.1f, z=%.1f" % [beat_position, z_pos])
	marker.position.z = z_pos
	

func _spawn_misblast_effect(beat_position: float, lane_index: int):
	var misblast = MISBLAST_SCENE.instantiate() as Node3D
	misblast.position.z = - (beat_position * length_per_beat)
	misblast.position.x = (lane_index - 1) * 0.6
	add_child(misblast)

func current_measure_is_unactivated() -> bool:
	var current_measure = song_node.current_measure()
	return reset_countdown == 0 and beats_in_measure.has(current_measure)

class GameplayTrackData:
	var note_map: Dictionary[float,int] = {}
	var note_times: PackedFloat32Array = []
	var note_positions: PackedVector2Array = [] # Y-value here is Z-position in world space
	var lane_notes: Array = [PackedInt32Array(),PackedInt32Array(),PackedInt32Array()]
	var notes_in_measure: Dictionary[int, PackedInt32Array] = {}
	var measure_note_counts: Dictionary[int,int] = {}
	var suppressed_measures: Dictionary[int,bool] = {}
	var measures_in_chunks: Dictionary[int,PackedInt32Array] = {}
	# For phrases, keys will be the starting measure number
	var phrase_lengths: Dictionary[int,int] = {}
	var phrase_note_indices: Dictionary[int,PackedInt32Array] = {}
	var phrase_note_counts: Dictionary[int,int] = {}
	var phrase_marker_positions: Dictionary[int,Vector2] = {}
	var phrase_activation_lengths: Dictionary[int,int] = {}
	var phrase_next_measures: Dictionary[int,int] = {}
