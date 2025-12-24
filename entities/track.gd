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
const AUTOBLAST_TIMING_MULTIPLIER = 0.67
const CHUNK_SIZE_MEASURES = 8
const CHUNK_LOAD_RANGE_FORWARD = 3
const CHUNK_UNLOAD_RANGE_BEHIND = 2
const NOTE_VISIBILITY_RANGE_BEATS = 64.0
const STANDARD_LENGTH_PER_BEAT = 4.0
const BEATS_PER_MEASURE = 4.0
var song_node: SynRoadSong
var track_index: int = -1
var track_data: GameplayTrackData
var lane_tint: Color
var midi_name: String
var audio_file: String
var instrument: int
var instrument_note_material: StandardMaterial3D
var instrument_ghost_material: StandardMaterial3D
var length_multiplier: float = 1.0
var length_per_beat: float = STANDARD_LENGTH_PER_BEAT
var note_nodes: Array[SynRoadNote] = []
var measure_nodes: Array[Node3D]
var measure_count: int = 0
var chunks: Array[Node3D] = []
var furthest_chunk_loaded := -1
var reset_measure: int = 0
var marker_measure_idx :int = 0
var current_phrase_index: int = -1
var phrase_notes: Array[SynRoadNote]
var phrase_notes_dict: Dictionary[SynRoadNote, bool]  # O(1) lookup instead of Array.has()
var phrase_notes_count: int = 0  # Track count separately to avoid .size() calls. Synced in _process_phrase_at_index(), decremented when notes removed.
var phrase_beats: Array[float]
var phrase_beat_index: int = 0  # Track which beat we're processing next in autoblast
var phrase_score_value:int = 0
var phrase_first_note_time: float = 0.0
var beats_in_measure: Dictionary  # Cache beats per measure: int -> Array[float]
var blasting_phrase: bool = false
var next_note_index: int = 0
var next_note_idx_per_lane: Array[int] = [0,0,0,]
var reset_countdown: int = 0
var _active_track := false
var is_active: bool:
	get: return _active_track
var just_activated: bool = false

@onready var asp = $Music as AudioStreamPlayer
@onready var miss_sound = $MissSound as AudioStreamPlayer
@onready var marker = $Marker as Node3D
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
		get_node("RailMaster").add_child(new_rail)
	_request_chunks(CHUNK_LOAD_RANGE_FORWARD)

func _ready():
	asp.stream = load(audio_file) as AudioStream
	# Cache materials once at track level instead of loading in each chunk
	asp.volume_db = UNFOCUSED_VOLUME
	asp.add_to_group("AudioPlayers")
	asp.add_to_group("TrackAudio")
	marker.position.x = track_data.phrase_marker_positions[0].x
	marker.position.z = track_data.phrase_marker_positions[0].y
	marker.visible = song_node.manager_node.hide_streak_hints == false

@warning_ignore("unused_parameter")
func _process(delta: float):
	var current_time = song_node.time_elapsed
	marker.position.y = lerp(1.2, 1.7, fmod(song_node.current_beat, 1))
	if song_node.lead_in_measures >= 0 or song_node.finished:
		return
#	if song_node.manager_node.autoblast:
#		pass
	else:
		for lane_index in range(3):
			var lane_notes = track_data.lane_notes[lane_index]
			var next_lane_note_idx = next_note_idx_per_lane[lane_index]
			if next_lane_note_idx >= lane_notes.size():
				continue
			var note_idx = lane_notes[next_lane_note_idx]
			var note_time = _get_note_time(note_idx)
			if song_node.current_measure < reset_measure and current_time > note_time:
				# Track hasn't been reset yet, but we've passed the note. Just advance the index.
				next_note_idx_per_lane[lane_index] += 1
			if (!is_active) and current_time > note_time:
				# Track is not active, but we've passed the note. Mark as missed and mute the track.
				next_note_idx_per_lane[lane_index] += 1
				if asp.volume_db != MUTED_VOLUME:
					asp.volume_db = MUTED_VOLUME
				# TODO: See if the passed note was the first note in the phrase
				# and signal inactive_phrase_missed if it was

			elif is_active and current_time > note_time + song_node.manager_node.miss_window:
				# We're past the hit window, should be a miss but check if it was already blasted
				var note_node = note_nodes[note_idx] as SynRoadNote
				next_note_idx_per_lane[lane_index] += 1
				if note_node and note_node.blasted:
					# Blasted but the index didn't advance. We're done.
					continue
				if asp.volume_db != MUTED_VOLUME:
					asp.volume_db = MUTED_VOLUME
	# Phrase-level progression based on precomputed first beat
	# Only auto-fail if we've WELL passed the window AND haven't started hitting this phrase
#	if reset_countdown == 0 and phrase_first_beat > 0.0 and !blasting_phrase:
#		# If we've passed the phrase start beyond the miss window
#		if current_beat > (phrase_first_beat + miss_beat_window):
#			# We missed the entire phrase window without hitting any notes
#			if is_active and current_measure >= phrase_start_measure and !song_node._manager_node.autoblast:
#				active_phrase_missed.emit()
#				print("Track %s breaking streak for missing phrase at measure %d (phrase_start_measure=%d, current_beat=%.2f, phrase_first_beat=%.2f)" % 
#					[midi_name, current_measure, phrase_start_measure, current_beat, phrase_first_beat])
#				streak_broken.emit()
#			else:
#				# Don't penalize for phrases at or past the song's end
#				if !phrase_notes_dict.is_empty() and phrase_start_measure < song_node.total_measures and !song_node._manager_node.autoblast:
##					print("Track %s missed inactive phrase starting at measure %d" % [midi_name, phrase_start_measure])
#					inactive_phrase_missed.emit(midi_name)
#			if marker_measure == phrase_start_measure:	
#				_move_marker(get_first_available_measure(current_measure + 1))
#			marker.visible = !song_node._manager_node.hide_streak_hints
#			
#			if asp.volume_db != MUTED_VOLUME:
#				asp.volume_db = MUTED_VOLUME
#			
#			# Advance to next phrase
#
#	if !song_node._manager_node.autoblast:
#		# We are not in autoblast mode, just check for missed notes
#		for lane_index in range(3):
#			var lane_beats = track_data.lane_notes[lane_index]
#			var note_index = next_note_idx_per_lane[lane_index]
#			if note_index >= lane_beats.size():
#				continue
#			var target_beat = lane_beats[note_index]
#			var target_time = target_beat * song_node.seconds_per_beat
#			if current_time > target_time + MISS_BEAT_WINDOW:
#				# Check if note was already blasted before marking as missed
#				var note_node = note_nodes.get(target_beat) as SynRoadNote
#				if note_node and note_node.blasted:
#					# Note was already hit, just advance the index
#					next_note_idx_per_lane[lane_index] += 1
#					continue
#				
#				# If we're actively blasting a phrase and this note is part of it, break streak
#				if blasting_phrase and note_node and phrase_notes_dict.has(note_node):
#					if is_active:
#						active_phrase_missed.emit()
#						print("Track %s breaking streak for missing note at beat %.2f (measure %d)" % 
#							[midi_name, target_beat, song_node.current_measure()])
#						streak_broken.emit()
#						blasting_phrase = false
#						if asp.volume_db != MUTED_VOLUME:
#							asp.volume_db = MUTED_VOLUME
#						if reset_countdown == 0:
#							var next_measure = song_node.current_measure() + 1
#							_process_phrase_at_measure(next_measure)
#							_move_marker(get_first_available_measure(next_measure))
#							marker.visible = !song_node._manager_node.hide_streak_hints
#				
#				next_note_idx_per_lane[lane_index] += 1
#	else:
#		if is_active:
#			# TIME TO FAKE IT BABY!
#			# Optimized: only process beats from current index until we find one that hasn't been reached
#			# Since phrase_beats is sorted, we can stop early. Use index instead of removing elements.
#			var notes_blasted = 0
#			while phrase_beat_index < phrase_beats.size() and phrase_beats[phrase_beat_index] <= current_beat:
#				var beat = phrase_beats[phrase_beat_index]
#				asp.volume_db = BLASTING_VOLUME
#				if !note_nodes[beat].blasted:
#					note_nodes[beat].blast(true)
#					# Emit note_hit signal with perfect timing (0.0 offset)
#					note_hit.emit(0.0)
#				# Check if this is the first note of the phrase
#				if !blasting_phrase:
#					var phrase_measure_count = preprocessed_phrases[current_phrase_index].measure_count
#					started_phrase.emit(phrase_score_value, phrase_start_measure, phrase_measure_count)
#					print("  Track %s: Starting autoblast phrase at measure %d" % [midi_name, phrase_start_measure])
#					blasting_phrase = true
#					marker.hide()
#					#print("    Blasted beat %.2f" % beat)
#					#print("    Remaining phrase beats: %s" % str(phrase_beats))
#				phrase_beat_index += 1
#				notes_blasted += 1
#			
#			# Check if phrase is complete
#			if phrase_beat_index >= phrase_beats.size() and notes_blasted > 0:
#				#print("  Track %s: Phrase complete, activating" % midi_name)
#				activate(song_node.current_measure())
#				blasting_phrase = false
#		else:
#			# Inactive track in autoblast mode: check if we've passed the phrase start
#			if reset_countdown == 0:
#				current_beat = song_node.current_beat()
#				var phrase_start_beat = (phrase_start_measure - 1) * length_per_beat
#				
#				# If we've passed the phrase start, we missed it - mute the track
#				if current_beat > phrase_start_beat + MISS_BEAT_WINDOW / song_node.seconds_per_beat:
#					if asp.volume_db != MUTED_VOLUME:
#						asp.volume_db = MUTED_VOLUME

func try_blast(lane_index:int):
	pass
	# var current_beat = song_node.current_beat()
	# var note_index = next_note_idx_per_lane[lane_index]
	# if note_index >= track_data.lane_notes[lane_index].size():
	# 	# No notes in this lane or all notes passed - still show misblast
	# 	miss_sound.play()
	# 	_spawn_misblast_effect(current_beat, lane_index)
	# 	# Break streak if blasting a phrase
	# 	if blasting_phrase:
	# 		asp.volume_db = MUTED_VOLUME
	# 		blasting_phrase = false
	# 		active_phrase_missed.emit()
	# 		print("Track %s breaking streak for misblast (no notes in lane) at beat %.2f (measure %d)" % 
	# 			[midi_name, current_beat, song_node.current_measure])
	# 		streak_broken.emit()
	# 		if reset_countdown == 0:
	# 			_process_phrase_at_measure(song_node.current_measure + 1)
	# 	return
	# var target_note = track_data.lane_notes[lane_index][note_index]
	# var time_offset = (target_note - current_beat) * song_node.seconds_per_beat
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
		# unmark the previous phrase
		for i in range(track_data.phrase_lengths[current_phrase_index]):
			pass
	current_phrase_index += 1
	if current_phrase_index < track_data.phrase_starts.size():
		phrase_notes_count = track_data.phrase_note_counts[current_phrase_index]
		for i in range(track_data.phrase_lengths[current_phrase_index]):
			pass

func set_active(active: bool):
	_active_track = active
	rails.visible = active
	for note in phrase_notes:
		note.set_phrase_note(active)
	if !active and blasting_phrase:
		blasting_phrase = false
		print("  Track %s: Deactivating while blasting phrase, breaking streak" % midi_name)
		streak_broken.emit()
	if not active and asp.volume_db != MUTED_VOLUME:
		asp.volume_db = UNFOCUSED_VOLUME
	# When becoming active, update to the current phrase if not in reset countdown

func _get_note_time(note_index: int) -> float:
	return track_data.note_times[note_index]

func _get_note_lane(note_index: int):
	var beat = track_data.note_map.keys()[note_index]
	return track_data.note_map[beat]

func _on_song_new_measure(_measure_num: int):
	var current_chunk = song_node.manager_node.measure_in_chunks[_measure_num]
#	print ("We are on chunk %d" % current_chunk)
	var target_ahead = current_chunk + CHUNK_LOAD_RANGE_FORWARD
	var target_behind = current_chunk - CHUNK_UNLOAD_RANGE_BEHIND
	if furthest_chunk_loaded < target_ahead and target_ahead < song_node.manager_node.chunk_count:
		_request_chunks(target_ahead)
	if target_behind >= 0 and chunks[target_behind]:
		print("Track %d destroying chunk %d" % [track_index, target_behind])
		chunks[target_behind].queue_free()
		chunks[target_behind] = null

func _request_chunks(furthest: int):
	while furthest_chunk_loaded < furthest:
		furthest_chunk_loaded += 1
		ChunkManager.request_chunk(track_index, furthest_chunk_loaded)

func activate(start_measure:int):
	pass
	

func _spawn_misblast_effect(beat_position: float, lane_index: int):
	var misblast = MISBLAST_SCENE.instantiate() as Node3D
	misblast.position.z = - (beat_position * length_per_beat)
	misblast.position.x = (lane_index - 1) * 0.6
	add_child(misblast)

class GameplayTrackData:
	var note_map: Dictionary[float,int] = {}
	var note_times: PackedFloat32Array = []
	var note_positions: PackedVector2Array = [] # Y-value here is Z-position in world space
	var lane_notes: Array = [PackedInt32Array(),PackedInt32Array(),PackedInt32Array()]
	var measures_with_notes: PackedInt32Array = []
	var notes_in_measure: Dictionary[int, PackedInt32Array] = {}
	var measure_note_counts: Dictionary[int,int] = {}
	var measures_in_chunks: Array[PackedInt32Array] = []
	# For phrases, keys will be the starting measure number
	var phrase_starts: PackedInt32Array = []
	var phrase_lengths: PackedInt32Array = []
	var phrase_note_indices: Array[PackedInt32Array] = []
	var phrase_note_counts: PackedInt32Array = []
	var phrase_marker_positions: PackedVector2Array = []
	var phrase_activation_lengths: PackedInt32Array = []
	var phrase_next_measures: PackedInt32Array = []
