class_name SynRoadSong
extends Node3D

const TRACK_SCENE:PackedScene = preload("res://entities/track.tscn")
const CHECKPOINT_SCENE:PackedScene = preload("res://entities/checkpoint.tscn")
const TRACK_WIDTH := 2.5
const AUTOBLAST_LOOKAHEAD_MEASURES = 2
const PLAYHEAD_LEAD_TIME := 0.132
  # Tuned to minimize player hit offset
const MAX_ENERGY := 8
const STANDARD_LENGTH_PER_BEAT := 4.0
const BEATS_PER_MEASURE := 4
var energy: int = MAX_ENERGY
var _manager_node:SynRoadSongManager
var bpm:float = 120.0
var seconds_per_beat:float = 0.5
var ticks_per_beat:int = -1
var midi_data:MidiData
var tracks:Array[Node]
var length_per_beat: float = STANDARD_LENGTH_PER_BEAT
var length_multiplier: float = 1.0
var time_elapsed := 0.0
var active_track := 0
var lead_in_measures := 999_999
var total_measures := 0
var previous_measure := 0
var phrase_start_measure := 0
var finished := false
var input_enabled := true
var song_data_ok: bool = false
var score: int
var streak: int = 0
var max_streak: int
var _inactive_safeguard_measure: int = -1
var _miss_count: int = 0
var _in_fail_state: bool = false
var _phrases_completed: int = 0
var _phrases_missed: int = 0
var _streak_breaks: int = 0
var _autoblast_next_track: int
var _autoblast_track_distance: int
var _track_transition_tween:Tween
var _intro_tween:Tween
var _max_hit_offset: float = 0.0
var _min_hit_offset: float = 0.0
var _avg_hit_offset: float = 0.0
var _notes_hit_count: int = 0
var _cached_active_track_node: SynRoadTrack  # Cache active track reference
var _fast_slow_hide_timer: SceneTreeTimer  # Reusable timer for fast/slow label
var _last_inactive_penalty_measure: int = -1  # Ensures only one energy/streak penalty per measure for inactive phrase misses
@onready var click_track_asp = $ClickTrack
@onready var lbl_debug_info = $DebugInfo
@onready var playhead = $Playhead
@onready var current_track = $Playhead/CurrentTrack
@onready var instrument_label = $Playhead/CurrentTrack/InstrumentLabel
@onready var camera:Camera3D = $Playhead/Camera3D
@onready var count_in = $CountIn
@onready var hud = $HUD
@onready var lbl_score = %ScoreLabel
@onready var lbl_streak = %StreakLabel
@onready var lbl_phrase_value = $HUD/PhraseValueLabel
@onready var lbl_auto_blast = $HUD/AutoblastLabel
@onready var lbl_fast_slow = $HUD/FastSlowLabel

signal new_measure
signal song_failed(stats)
signal song_finished(stats)

var previous_time_elapsed: float = 0.0
var max_drift: float = 0.0
var drift_samples: int = 0
var total_drift: float = 0.0
var frame_drops: int = 0
var playhead_target_z: float = 0.0
var playhead_velocity: float = 0.0

func _enter_tree() -> void:
	_manager_node = get_parent() as SynRoadSongManager

func _ready():
	if not _manager_node.song_data:
		print("No SongData assigned, aborting")
		return
	print("Loading song: %s" % _manager_node.song_data.title)
	lead_in_measures = _manager_node.song_data.lead_in_measures
	total_measures = _manager_node.song_data.playable_measures + lead_in_measures
	bpm = _manager_node.song_data.bpm
	seconds_per_beat = _manager_node.song_data.seconds_per_beat
	length_per_beat = STANDARD_LENGTH_PER_BEAT * length_multiplier
	for i in _manager_node.track_data.size():
		var newTrack = TRACK_SCENE.instantiate() as SynRoadTrack
		newTrack.position.x = (TRACK_WIDTH * tracks.size())
		newTrack.midi_name = _manager_node.track_data.keys()[i]
		newTrack.audio_file = ResourceUID.path_to_uid(_manager_node.track_data[newTrack.midi_name].audio_file)
		newTrack.measure_count = total_measures
		newTrack.note_map = _manager_node.track_data[newTrack.midi_name].note_map
		newTrack.instrument = _manager_node.track_data[newTrack.midi_name].instrument
		newTrack.beats_in_measure = _manager_node.track_data[newTrack.midi_name].beats_in_measure
		newTrack.lane_note_beats = _manager_node.track_data[newTrack.midi_name].lane_note_beats
		newTrack.preprocessed_phrases = _manager_node.track_data[newTrack.midi_name].phrases
		newTrack.activation_length_measures = _manager_node.fast_track_reset
		tracks.append(newTrack)
		new_measure.connect(newTrack._on_song_new_measure)
		newTrack.track_activated.connect(_on_track_activated)
		newTrack.inactive_phrase_missed.connect(_on_inactive_phrase_missed)
		newTrack.streak_broken.connect(_on_streak_broken)
		newTrack.started_phrase.connect(_on_started_phrase)
		newTrack.active_phrase_missed.connect(_on_active_phrase_missed)
		newTrack.note_hit.connect(_on_note_hit)
		add_child(newTrack)
	click_track_asp.stream = load(ResourceUID.path_to_uid(_manager_node.song_data.click_track))
	for audioFileName in _manager_node.song_data.intro_audio:
		var introAsp = AudioStreamPlayer.new()
		introAsp.stream = load(ResourceUID.path_to_uid(audioFileName))
		introAsp.volume_db = -7.0
		add_child(introAsp)
		introAsp.add_to_group("AudioPlayers")
	song_data_ok = true
	var start_gate = CHECKPOINT_SCENE.instantiate() as Node3D
	new_measure.connect(start_gate._on_song_new_measure)
	start_gate.get_node("Text").text = "Song Start"
	start_gate.gate_location = lead_in_measures
	start_gate.position.z = -(BEATS_PER_MEASURE * length_per_beat) * lead_in_measures
	add_child(start_gate)
	var end_gate = CHECKPOINT_SCENE.instantiate() as Node3D
	new_measure.connect(end_gate._on_song_new_measure)
	end_gate.get_node("Text").text = "Song End"
	end_gate.gate_location = total_measures
	end_gate.position.z = -(BEATS_PER_MEASURE * length_per_beat) * total_measures
	add_child(end_gate)
	for measure in _manager_node.song_data.checkpoints:
		var checkpoint = CHECKPOINT_SCENE.instantiate() as Node3D
		new_measure.connect(checkpoint._on_song_new_measure)
		var percentage = float(measure * 100) / total_measures
		checkpoint.get_node("Text").text = "%d%% Complete" % percentage
		checkpoint.gate_location = (measure + lead_in_measures - 1)
		checkpoint.position.z = -(BEATS_PER_MEASURE * length_per_beat) * (measure + lead_in_measures - 1)
		add_child(checkpoint)
	match _manager_node.energy_modifier:
		3, 4:
			#energy system disabled
			%EnergyBar.hide()
		_:
			%EnergyBar.show()
			%EnergyBar.value = energy

func start_song():
	print("Starting song playback.")
	_intro_tween = get_tree().create_tween()		
	playhead.position.x = ((tracks.size() - 1) * TRACK_WIDTH)/2
	print("Playhead starting at x=%.2f" % playhead.position.x)
	current_track.position.x = (active_track * TRACK_WIDTH) - playhead.position.x
	print("Current track starting at x=%.2f" % current_track.position.x)
	camera.position.x = (active_track * TRACK_WIDTH) - playhead.position.x
	print("Camera starting at x=%.2f" % camera.position.x)
	%SongProgress.max_value = total_measures
	%SongProgress.min_value = lead_in_measures + 1
	if _manager_node.autoblast:
		lbl_auto_blast.show()
		_autoblast_next_track = _find_best_track_for_autoblast()
		_autoblast_track_distance = _get_phrase_distances()[_autoblast_next_track]
		if _autoblast_next_track != active_track:
			_switch_active_track(_autoblast_next_track, false)
	else:
		lbl_auto_blast.hide()
	_set_instrument_label()
	tracks[active_track].set_active(true)
	get_tree().call_group("AudioPlayers", "play")
	_intro_tween.tween_interval((lead_in_measures - 1) * BEATS_PER_MEASURE * seconds_per_beat)
	_intro_tween.tween_property(hud, "modulate:a", 1.0, 0.1)
	_intro_tween.parallel().tween_property(instrument_label, "scale", Vector3.ONE, 0.1)

func _process(delta: float):
	if !finished:
		if Input.is_action_just_pressed("instant_fail") and OS.is_debug_build():
			print("Instant fail triggered.")
			fail_song()
			return

		# Get current audio time with mix delay compensation
		var audio_time = click_track_asp.get_playback_position() + AudioServer.get_time_since_last_mix()
		
		# Calculate drift from PREVIOUS frame's time + delta
		if previous_time_elapsed > 0:
			var expected_time = previous_time_elapsed + delta
			var drift = audio_time - expected_time
			
			if abs(drift) > 0.050:  # >50ms drift
				print("FRAME DROP: %.1fms @ beat %.2f (measure %d, mod8=%d, delta: %.3f, actual: %.3f, expected: %.3f)" % 
					[drift * 1000, audio_time / (seconds_per_beat),current_measure(), current_measure() % 8, delta, audio_time, expected_time])
				frame_drops += 1

				if _manager_node.autoblast:
					var _active_track_node = tracks[active_track] as SynRoadTrack
					_active_track_node._catch_up_missed_notes(previous_time_elapsed, audio_time)
		#			_active_track_node._find_next_phrase()
			
			elif abs(drift) > 0.010:
				drift_samples += 1
				total_drift += abs(drift)
				max_drift = max(max_drift, abs(drift))
		
		previous_time_elapsed = audio_time
		time_elapsed = audio_time
		
		%actualplayhead.position.z = current_beat() * -length_per_beat

		# Calculate target position from audio time
		# Tuned to minimize player hit offset - aim for ~0ms average
		var predicted_beat = (audio_time + PLAYHEAD_LEAD_TIME) * (bpm/60)
		playhead_target_z = -length_per_beat * predicted_beat
		
		# Smooth interpolation with spring damping
		var spring_strength = 100.0  # Increased for tighter tracking
		var damping = 15.0  # Increased to match stronger spring
		
		var displacement = playhead_target_z - playhead.position.z
		var spring_force = displacement * spring_strength
		var damping_force = -playhead_velocity * damping
		
		playhead_velocity += (spring_force + damping_force) * delta
		playhead.position.z += playhead_velocity * delta
		var new_active_track = active_track
		if !_manager_node.autoblast and input_enabled:
			if Input.is_action_just_pressed("track_next"):
				new_active_track = (active_track + 1) % tracks.size()
				_switch_active_track(new_active_track)
			elif Input.is_action_just_pressed("track_prev"):
				new_active_track = (active_track - 1 + tracks.size()) % tracks.size()
				_switch_active_track(new_active_track)
		if previous_measure != current_measure():
			if previous_measure > total_measures - 1:
				finished = true
				if not _manager_node.autoblast:
					if _miss_count == 0:
						%HUDAnimations.play("PerfectRun")
					else:
						%HUDAnimations.play("SongClear")
				var tween = get_tree().create_tween()
				tween.set_parallel(true)
				tween.tween_property(camera, "position", Vector3(0, 3, 1), 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
				tween.tween_property(camera, "rotation_degrees:x", 0.0, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
				tween.tween_property(instrument_label, "scale", Vector3.ZERO, 0.2)
				for track in tracks:
					track.asp.volume_db = -6.0
				playhead.position.z = -(BEATS_PER_MEASURE * length_per_beat) * total_measures
				var _phrase_capture_accuracy = float(_phrases_completed * 100) / (_phrases_completed + _phrases_missed)
				print("Song finished!")
				var final_score_text = "Final Score: %d\nMax Streak: %d" % [score, max_streak]
				if _manager_node.autoblast:
					print("Autoblast was enabled.")
				else:
					print("Total frame drops: %d" % frame_drops)
					print("Average drift: %.3f ms over %d samples" % [ (total_drift / drift_samples) * 1000, drift_samples])
					print("Max drift: %.3f ms" % (max_drift * 1000))
					print("Hit offsets: Max %.3f s, Min %.3f s, Avg %.3f s over %d notes" % 
						[_max_hit_offset, _min_hit_offset, _avg_hit_offset, _notes_hit_count])
					if _streak_breaks == 0:
						final_score_text += "\nPerfect Run!"
					else:
						final_score_text += "\nPhrases Completed: %d\nPhrases Missed: %d\nPhrase Capture Accuracy: %.2f%%" % \
							[_phrases_completed, _phrases_missed, _phrase_capture_accuracy]
				var stats = {
					"score": score,
					"max_streak": max_streak,
					"phrases_completed": _phrases_completed,
					"phrases_missed": _phrases_missed,
					"streak_breaks": _streak_breaks,
				}
				emit_signal("song_finished", stats)
				print(final_score_text)
			else:
				if _manager_node.energy_modifier == 1:
					# TODO: If any track is not activated or empty, subtract 1 energy
					# but don't fail the song unless there's a streak break with 0 energy
					pass
				previous_measure = current_measure()
				%SongProgress.value = previous_measure
#				print("measure %d/%d" % [previous_measure, total_measures])
				new_measure.emit(previous_measure)
				if lead_in_measures > 0:
					count_in.position.z = -(BEATS_PER_MEASURE * length_per_beat) * previous_measure
					count_in.text = str(lead_in_measures)
					lead_in_measures -= 1
				elif lead_in_measures == 0:
					get_tree().call_group("TrackAudio", "set_volume_db", SynRoadTrack.MUTED_VOLUME)
					lead_in_measures = -1
						
		if lead_in_measures < 1:
			# Cache active track reference for this frame
			_cached_active_track_node = tracks[active_track] as SynRoadTrack
			
			# Check for autoblast track switching every frame, not just on measure boundaries
			if _manager_node.autoblast and _autoblast_next_track != active_track:
				if !_cached_active_track_node.blasting_phrase:
					var next_track_node = tracks[_autoblast_next_track] as SynRoadTrack
					var switch_measure = next_track_node.phrase_start_measure
					# Switch when we're within 0.5 beats of the target measure
					var switch_beat = float(switch_measure - 1) * BEATS_PER_MEASURE - 0.5
					if current_beat() >= switch_beat:
						_switch_active_track(_autoblast_next_track)
						# Update cached reference after switch
						_cached_active_track_node = tracks[active_track] as SynRoadTrack
#					print("Switching active track from %d to %d at beat %.2f" % [active_track, _autoblast_next_track, current_beat()])
			if not _manager_node.autoblast and input_enabled:
				if Input.is_action_just_pressed("note_left"):
					_cached_active_track_node.try_blast(0)
				elif Input.is_action_just_pressed("note_center"):
					_cached_active_track_node.try_blast(1)
				elif Input.is_action_just_pressed("note_right"):
					_cached_active_track_node.try_blast(2)
	
	#lblDebugInfo.text = debug_info()

func _set_instrument_label():
	if tracks.size() > 0:
		var active_track_node = tracks[active_track] as SynRoadTrack
		instrument_label.text = SynRoadTrack.INSTRUMENTS[active_track_node.instrument][0]
		instrument_label.modulate = SynRoadTrack.INSTRUMENTS[active_track_node.instrument][1]

func current_beat() -> float:
	return time_elapsed * (bpm/60)

func current_measure() -> int:
	return floor((time_elapsed * (bpm/60)) / BEATS_PER_MEASURE) + 1
	
func debug_info() -> String:
	var lines: Array[String] = []
	if finished:
		lines.append("Song finished")
	else:
		lines.append("Elapsed Audio Time: %.3f" % time_elapsed)
		lines.append("Beat: %.4f" % current_beat())
		lines.append("Measure: %d : %.1f" % [current_measure(), fmod(current_beat(), BEATS_PER_MEASURE)])
		lines.append("Phrase start position: %d\n" % phrase_start_measure)
	lines.append("Tracks:")
	for i in tracks.size():
		lines.append("%02d: %s" % [i, tracks[i].debug_info()])
	return "\n".join(lines)

func _on_started_phrase(phrase_score_value:int, start_measure:int, measure_count:int):
	streak += 1
	lbl_streak.text = "x%d" % min(streak,4)
	lbl_phrase_value.text = "%d" % (phrase_score_value * min(streak, 4))
	lbl_phrase_value.show()
	# Tell inactive tracks to position their markers after this phrase
	var next_phrase_measure = start_measure + measure_count
	for i in tracks.size():
		if i != active_track:
			var track = tracks[i] as SynRoadTrack
			track.update_marker_for_inactive(next_phrase_measure)

func _on_track_activated(note_count:int, start_measure:int):
	_inactive_safeguard_measure = start_measure # Prevents another phrase on the same measure from breaking streak
	score += note_count * min(streak, 4)
	if streak > max_streak:
		max_streak = streak
	_phrases_completed += 1
	lbl_phrase_value.hide()
	lbl_score.text = "%d" % score
	lbl_streak.text = "x%d" % min(streak,4)
	match _manager_node.energy_modifier:
		0:
			# Gain 1 energy per successful phrase
			energy_change(1)
		1:
			# Gain 3 energy per successful phrase
			energy_change(3)
	if _manager_node.autoblast and current_measure() < total_measures:
		# Queue up the next track to switch to on the next measure boundary
		_autoblast_next_track = _find_best_track_for_autoblast()
		_autoblast_track_distance = _get_phrase_distances()[_autoblast_next_track] if _autoblast_next_track != active_track else 999
#		print("Autoblast: Current track %d, queued next track %d (distance=%d)" % [active_track, _autoblast_next_track, _autoblast_track_distance])


func _on_streak_broken():
	var had_streak = streak > 0
	_miss_count += 1
	match _manager_node.energy_modifier:
		0, 2:
			energy_change(-1)
			if energy <= 0:
				fail_song()
				return
		3:
			fail_song()
			return
	lbl_phrase_value.hide()
	print("Streak break, was %d at measure %d" % [streak, current_measure()])
	streak = 0
	if had_streak:
		print("Stat updated for proper streak break.")
		_streak_breaks += 1
	lbl_streak.text = "x%d" % streak

func _on_active_phrase_missed():
	_phrases_missed += 1

func _on_inactive_phrase_missed(trk_name:String):
	if _inactive_safeguard_measure >= current_measure(): # this measure already had a phrase activation, do not penalize
		return
	var measure = current_measure()

	# Enforce only one penalty per measure for inactive phrase misses
	if measure == _last_inactive_penalty_measure:
		return
	var active_track_node = tracks[active_track] as SynRoadTrack
	if active_track_node.blasting_phrase:
		return
	for track in tracks:
		if (track as SynRoadTrack).just_activated:
			return
	# If on a track counting down its reset, apply a single penalty this measure
	if active_track_node.reset_countdown > 0:
		_last_inactive_penalty_measure = measure
		print("Track %s breaking streak for inactive phrase miss at measure %d (active track on reset countdown)" % [trk_name, measure])
		_on_streak_broken()
		return
	# Do not penalize if the track's next phrase begins this measure or earlier
	if active_track_node.phrase_start_measure <= measure:
		return
	# Do not penalize if there are notes in this measure (player could play them instead)
	var active_track_notes = active_track_node.get_notes_in_measure(measure)
	if not active_track_notes.is_empty():
		return
	_last_inactive_penalty_measure = measure
	print("Track %s breaking streak for inactive phrase miss at measure %d" % [name, measure])
	_on_streak_broken()

func _switch_active_track(new_active_track:int, use_tween: bool = true):
	if new_active_track == active_track:
		return
#	print("Switching active track from %d to %d at beat %.2f" % [active_track, new_active_track, current_beat()])
#	print_stack()
	if playhead.position.x <= 0:
		print("Playhead x position is probably uninitialized (%.2f), not moving anything." % playhead.position.x)
		return
	if _track_transition_tween:
		_track_transition_tween.kill()
	_track_transition_tween = get_tree().create_tween()
	_track_transition_tween.set_parallel(true)
	(tracks[active_track] as SynRoadTrack).set_active(false)
	active_track = new_active_track
	(tracks[active_track] as SynRoadTrack).set_active(true)
	_set_instrument_label()
	var new_x_pos = (active_track * TRACK_WIDTH) - playhead.position.x
	if lead_in_measures >= 0:
		count_in.position.x = (active_track * TRACK_WIDTH)
	if use_tween:
#		print("Tweening camera.position.x to %f (active_track=%d, playhead.x=%f)" % [new_x_pos, active_track, playhead.position.x])
		_track_transition_tween.tween_property(current_track, "position:x", new_x_pos, 0.1).set_trans(Tween.TRANS_QUAD)
		_track_transition_tween.tween_property(camera, "position:x", new_x_pos, 0.25).set_trans(Tween.TRANS_SINE)
	else:
#		print("Setting camera.position.x to %f (active_track=%d, playhead.x=%f)" % [new_x_pos, active_track, playhead.position.x])
		current_track.position.x = new_x_pos
		camera.position.x = new_x_pos

func _get_phrase_distances() -> Array[int]:
	var result:Array[int]
	for track in tracks:
		var phrase_distance = (track as SynRoadTrack).phrase_start_measure - current_measure()
		result.append(phrase_distance)
	return result

func _get_next_phrase_values() -> Array[int]:
	var result:Array[int]
	for track in tracks:
		var phrase_value = (track as SynRoadTrack).phrase_score_value
		result.append(phrase_value)
	return result

func _has_phrase_next_measure(exclude_track:int) -> bool:
	for i in tracks.size():
		if i == exclude_track:
			continue
		var track = tracks[i] as SynRoadTrack
		if track.reset_countdown > 0:
			continue
		var phrase_distance = track.phrase_start_measure - current_measure()
		if phrase_distance == 1:
			return true
	return false

func _find_best_track_for_autoblast() -> int:
	# Find closest unactivated measure using track marker_measure
	var candidates: Array = []
	
#	print("  Finding best track: active=%d" % active_track)
	
	# Build list of candidates: [track_idx, measure_distance, note_count, track_distance_from_active, reset_countdown]
	for i in tracks.size():
		var track = tracks[i] as SynRoadTrack
		# Always skip the current active track - we want to switch to a different track
		if i == active_track:
#			print("    Track %d: skipped (current track)" % i)
			continue
		
		# Use marker_measure to get the first measure with notes
		var first_measure = track.marker_measure
		
		# Skip tracks with no future notes or whose phrase starts in the current measure or earlier
		if first_measure <= 0 or first_measure <= current_measure():
#			print("    Track %d: skipped (first_measure=%d not after current=%d)" % [i, first_measure, current_measure()])
			continue
		
		# Count notes in the first two measures of this phrase
		var note_count = 0
		var start_beat = float(first_measure - 1) * BEATS_PER_MEASURE
		var end_beat = float(first_measure + 1) * BEATS_PER_MEASURE
		for beat in track.note_map.keys():
			if beat >= start_beat and beat < end_beat:
				note_count += 1
		
		var measure_distance = first_measure - current_measure()
		var track_distance = abs(i - active_track)
		
		# Add all tracks to candidates - we'll prioritize by measure_distance first
		candidates.append([i, measure_distance, note_count, track_distance, track.reset_countdown])
#		print("    Track %d: candidate (first_measure=%d, measure_dist=%d, notes=%d, track_dist=%d, countdown=%d)" % [i, first_measure, measure_distance, note_count, track_distance, track.reset_countdown])
	
	if candidates.is_empty():
#		print("  No candidates found, staying on track %d" % active_track)
		return active_track
	
	# Find minimum measure distance
	var min_measure_distance = 9999
	for candidate in candidates:
		if candidate[1] < min_measure_distance:
			min_measure_distance = candidate[1]
	
	# Filter to only candidates with minimum measure distance
	var closest_candidates: Array = []
	for candidate in candidates:
		if candidate[1] == min_measure_distance:
			closest_candidates.append(candidate)
	
	if closest_candidates.size() == 1:
		return closest_candidates[0][0]
	
	# If tied, find maximum note count among the closest
	var max_note_count = -1
	for candidate in closest_candidates:
		if candidate[2] > max_note_count:
			max_note_count = candidate[2]
	
	# Filter to only candidates with max note count
	var best_note_candidates: Array = []
	for candidate in closest_candidates:
		if candidate[2] == max_note_count:
			best_note_candidates.append(candidate)
	
	if best_note_candidates.size() == 1:
		return best_note_candidates[0][0]
	
	# If still tied, find minimum track distance (prefer closer tracks)
	var min_track_distance = 9999
	for candidate in best_note_candidates:
		if candidate[3] < min_track_distance:
			min_track_distance = candidate[3]
	
	# Filter to only candidates with minimum track distance
	var final_candidates: Array = []
	for candidate in best_note_candidates:
		if candidate[3] == min_track_distance:
			final_candidates.append(candidate)
	
	if final_candidates.size() == 1:
		return final_candidates[0][0]
	
	# If equidistant, prefer right (higher index)
	var best_idx = final_candidates[0][0]
	for candidate in final_candidates:
		if candidate[0] > best_idx:
			best_idx = candidate[0]
	
	return best_idx

func _minimum_positive_integer_in_array(arr:Array[int]) -> int:
	var min_value = 9999
	for value in arr:
		if value > 0 and value < min_value:
			min_value = value
	return min_value

func _find_adjacent_unactivated_track() -> int:
	# Check left and right adjacent tracks for unactivated ones
	var candidates: Array[int] = []
	
	# Check left neighbor
	if active_track > 0:
		var left_track = tracks[active_track - 1] as SynRoadTrack
		if left_track.reset_countdown == 0:
			candidates.append(active_track - 1)
	
	# Check right neighbor
	if active_track < tracks.size() - 1:
		var right_track = tracks[active_track + 1] as SynRoadTrack
		if right_track.reset_countdown == 0:
			candidates.append(active_track + 1)
	
	if candidates.is_empty():
		return -1
	
	# Filter candidates to only those with phrases starting in the next measure
	# This prevents switching to a track that would cause a streak break
	var phrase_distances = _get_phrase_distances()
	var valid_candidates: Array[int] = []
	for candidate in candidates:
		var distance = phrase_distances[candidate]
		# Only consider if phrase starts exactly next measure
		if distance == 1:
			valid_candidates.append(candidate)
	
	if valid_candidates.is_empty():
		return -1
	
	# If both adjacent tracks have phrases next measure, pick the one with higher value
	if valid_candidates.size() == 2:
		var phrase_values = _get_next_phrase_values()
		if phrase_values[valid_candidates[0]] >= phrase_values[valid_candidates[1]]:
			return valid_candidates[0]
		else:
			return valid_candidates[1]
	
	return valid_candidates[0]

func energy_change(amount:int) -> void:
	energy = clampi(energy + amount, 0, MAX_ENERGY)
#	print("Energy changed by %d, new value: %d" % [amount, energy])
	%EnergyBar.value = energy

func _on_note_hit(offset: float):
	_max_hit_offset = max(_max_hit_offset, offset)
	_min_hit_offset = min(_min_hit_offset, offset)
	_avg_hit_offset = ((_avg_hit_offset * _notes_hit_count) + offset) / (_notes_hit_count + 1)
	_notes_hit_count += 1
	if abs(offset) > 0.01:
		lbl_fast_slow.show()
		if offset > 0:
			lbl_fast_slow.text = "FAST"
		else:
			lbl_fast_slow.text = "SLOW"
		
		# Reuse timer instead of creating new ones
		if not _fast_slow_hide_timer or _fast_slow_hide_timer.time_left <= 0:
			_fast_slow_hide_timer = get_tree().create_timer(0.5)
			_fast_slow_hide_timer.timeout.connect(func(): lbl_fast_slow.hide())
	else:
		lbl_fast_slow.hide()

func fail_song():
	if _in_fail_state:
		return
	_in_fail_state = true
	print("Song failed!")
	input_enabled = false
	hud.hide()
	var stats = {
		"score": score,
		"measure": current_measure(),
		"max_streak": max_streak,
		"phrases_completed": _phrases_completed,
		"phrases_missed": _phrases_missed,
		"streak_breaks": _streak_breaks
	}
	song_failed.emit(stats)
	var slow_tween = get_tree().create_tween().set_parallel(true)
	var asps = get_tree().get_nodes_in_group("AudioPlayers")
	slow_tween.tween_property(instrument_label, "scale", Vector3.ZERO, 0.2)
	for asp in asps:
		slow_tween.tween_property(asp, "pitch_scale", 0.01, 3.0)
	await slow_tween.finished
	finished = true
	get_tree().call_group("AudioPlayers", "stop")
