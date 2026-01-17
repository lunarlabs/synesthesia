class_name SynRoadSong
extends Node3D

const TRACK_SCENE:PackedScene = preload("res://entities/track.tscn")
const CHECKPOINT_SCENE:PackedScene = preload("res://entities/checkpoint.tscn")
const TRACK_WIDTH := 2.5
const AUTOBLAST_LOOKAHEAD_MEASURES = 2
const PLAYHEAD_LEAD_DIST := 0.305
  # Tuned to minimize player hit offset
const MAX_ENERGY := 8
const STANDARD_LENGTH_PER_BEAT := 4.0
const BEATS_PER_MEASURE := 4
const DESYNC_LIMIT := 0.03
var energy: int = MAX_ENERGY
var manager_node:SynRoadSongManager
var bpm:float = 120.0
var seconds_per_beat:float = 0.5
var ticks_per_beat:int = -1
var tracks:Array[Node]
var length_per_beat: float = STANDARD_LENGTH_PER_BEAT
var length_multiplier: float = 1.0
var _playhead_speed: float
var active_track := 0
var lead_in_measures := 999_999
var total_measures := 0
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
var _track_transition_tween:Tween
var _intro_tween:Tween
var _max_hit_offset: float = -INF
var _min_hit_offset: float = INF
var _early_note_hits: int = 0
var _late_note_hits: int = 0
var _avg_hit_offset: float = 0.0
var _notes_hit_count: int = 0
var _cached_active_track_node: SynRoadTrack  # Cache active track reference
var _fast_slow_hide_timer: SceneTreeTimer  # Reusable timer for fast/slow label
var _last_inactive_penalty_measure: int = -1  # Ensures only one energy/streak penalty per measure for inactive phrase misses
var _track_marker_measures: PackedInt32Array  # Cache of marker measures for each track, updated by track._move_marker()
var _track_reset_measures: PackedInt32Array  # Cache of reset measures for each track, updated by track.activate()
var _targets: Array
var _next_checkpoint: int = 0
var _last_streak_break_measure: int = -1
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

signal song_failed(stats)
signal song_finished(stats)

var max_drift: float = 0.0
var drift_samples: int = 0
var total_drift: float = 0.0
var frame_drops: int = 0
var playhead_target_z: float = 0.0
var playhead_velocity: float = 0.0
var lead_distance: float = 0.0

func _enter_tree() -> void:
	manager_node = get_parent() as SynRoadSongManager

func _ready():
	RenderingServer.global_shader_parameter_set("danger", false )
	RenderingServer.global_shader_parameter_set("current_track", 0)
	if not manager_node.song_data:
		print("No SongData assigned, aborting")
		return
	print("Loading song: %s" % manager_node.song_data.title)
	lead_in_measures = manager_node.song_data.lead_in_measures
	length_multiplier = manager_node.length_multiplier
	total_measures = manager_node.song_data.playable_measures + lead_in_measures
	bpm = manager_node.song_data.bpm
	%Conductor.setup(click_track_asp, bpm)
	seconds_per_beat = manager_node.song_data.seconds_per_beat
	length_per_beat = STANDARD_LENGTH_PER_BEAT * length_multiplier
	_playhead_speed = -(length_per_beat / seconds_per_beat)
	lead_distance = PLAYHEAD_LEAD_DIST * length_multiplier
	_targets = [%TargetLeft, %TargetCenter, %TargetRight]
	_track_marker_measures.resize(6)  # Initialize cache for 6 instrument tracks
	_track_reset_measures.resize(6)  # Initialize cache for 6 instrument tracks
	for i in manager_node.track_data.size():
		print ("instantiating track %d" % i)
		var newTrack = TRACK_SCENE.instantiate() as SynRoadTrack
		newTrack.track_index = i
		newTrack.position.x = (TRACK_WIDTH * tracks.size())
		newTrack.instrument = manager_node.track_data[i].track_info.instrument
		newTrack.name = "Track%d" % i
		newTrack.audio_file = ResourceUID.path_to_uid(manager_node.track_data[i].track_info.audio_file)
		newTrack.track_data = manager_node.track_data[i].track_data
		tracks.append(newTrack)
		%Conductor.new_measure.connect(newTrack._on_song_new_measure)
		newTrack.track_activated.connect(_on_track_activated)
		newTrack.inactive_phrase_missed.connect(_on_inactive_phrase_missed)
		newTrack.streak_broken.connect(_on_streak_broken)
		newTrack.started_phrase.connect(_on_started_phrase)
		newTrack.active_phrase_missed.connect(_on_active_phrase_missed)
		newTrack.note_hit.connect(_on_note_hit)
		add_child(newTrack)
		ChunkManager.request_chunk(i, 0)
		await ChunkManager.queue_empty
	print("tracks added")
	click_track_asp.stream = load(ResourceUID.path_to_uid(manager_node.song_data.click_track))
	for audioFileName in manager_node.song_data.intro_audio:
		var introAsp = AudioStreamPlayer.new()
		introAsp.stream = load(ResourceUID.path_to_uid(audioFileName))
		introAsp.volume_db = -7.0
		add_child(introAsp)
		introAsp.add_to_group("AudioPlayers")
	song_data_ok = true
	var checkpoint_fade_time = (seconds_per_beat * BEATS_PER_MEASURE)
	var start_gate = CHECKPOINT_SCENE.instantiate() as Node3D
	print("instantiating checkpoints")
	%Conductor.new_measure.connect(start_gate._on_song_new_measure)
	start_gate.get_node("Text").text = "Song Start"
	start_gate.name = "SongStart"
	start_gate.fadeout_time = checkpoint_fade_time
	start_gate.gate_location = lead_in_measures
	start_gate.position.z = -(BEATS_PER_MEASURE * length_per_beat) * lead_in_measures
	add_child(start_gate)
	var end_gate = CHECKPOINT_SCENE.instantiate() as Node3D
	%Conductor.new_measure.connect(end_gate._on_song_new_measure)
	end_gate.get_node("Text").text = "Song End"
	end_gate.name = "SongEnd"
	end_gate.fadeout_time = checkpoint_fade_time
	end_gate.gate_location = total_measures
	end_gate.position.z = -(BEATS_PER_MEASURE * length_per_beat) * total_measures
	add_child(end_gate)
	for i in range(manager_node.checkpoint_measures.size()):
		var measure = manager_node.checkpoint_measures[i]
		var checkpoint = CHECKPOINT_SCENE.instantiate() as Node3D
		%Conductor.new_measure.connect(checkpoint._on_song_new_measure)
		checkpoint.name = "Checkpoint%d" % (i)
		checkpoint.fadeout_time = checkpoint_fade_time
		var percentage = float(measure * 100) / total_measures
		checkpoint.get_node("Text").text = "%d%% Complete" % percentage
		checkpoint.gate_location = (measure)
		checkpoint.position.z = manager_node.checkpoint_positions[i]
		add_child(checkpoint)
	match manager_node.energy_modifier:
		1:
			energy = 5
			%EnergyBar.value = energy
		3, 4:
			#energy system disabled
			%EnergyBar.hide()
		_:
			%EnergyBar.show()
			%EnergyBar.value = energy
	print("Precompiling shaders...")
	for i in range(3):
		await get_tree().process_frame

	_song_start()

func _song_start():
	print("Starting song playback.")
	playhead.position.x = ((tracks.size() - 1) * TRACK_WIDTH)/2
	print("Playhead starting at x=%.2f" % playhead.position.x)
	current_track.position.x = (active_track * TRACK_WIDTH) - playhead.position.x
	print("Current track starting at x=%.2f" % current_track.position.x)
	camera.position.x = (active_track * TRACK_WIDTH) - playhead.position.x
	print("Camera starting at x=%.2f" % camera.position.x)
	%SongProgress.max_value = total_measures
	%SongProgress.min_value = lead_in_measures - 1
	if manager_node.autoblast:
		lbl_auto_blast.show()
		_autoblast_next_track = _find_best_track_for_autoblast()
		if _autoblast_next_track != active_track:
			_switch_active_track(_autoblast_next_track, false)
	else:
		lbl_auto_blast.hide()
	_set_instrument_label()
	tracks[active_track].set_active(true)
	%Conductor.new_measure.emit(0)
	_cached_active_track_node = tracks[active_track]
	process_mode = Node.PROCESS_MODE_PAUSABLE
	get_tree().call_group("AudioPlayers", "play")
	%Conductor.is_playing = true
	playhead.position.z = -length_per_beat * %Conductor.current_beat
	playhead_velocity = -length_per_beat * (bpm / 60.0)
	manager_node.can_pause = true
	var _intro_anim_call := Callable(%HUDAnimations, "play").bind("BuildIn")
	_intro_tween = get_tree().create_tween()
	_intro_tween.tween_property(%FadeOut, "modulate", Color(1,1,1,0),
	 (seconds_per_beat * BEATS_PER_MEASURE)).set_trans(Tween.TRANS_SINE)\
	.set_ease(Tween.EASE_IN)
	_intro_tween.tween_callback(_intro_anim_call)

func _process(delta: float):
	if !finished:
		if Input.is_action_just_pressed("instant_fail") and OS.is_debug_build():
			print("Instant fail triggered.")
			fail_song()
			return

		# Cache frequently-used members to avoid repeated lookups
		var beat = %Conductor.current_beat
		var mn = manager_node
		var trs = tracks

		%actualplayhead.position.z = %Conductor.current_beat * -length_per_beat
		RenderingServer.global_shader_parameter_set("beat", fmod(%Conductor.current_beat, 1.0))
		# Smooth interpolation with spring damping
		var spring_strength = 100.0
		var damping = 15.0
		# Calculate target position from audio time (single predicted beat calc)
# ... inside _process ...
		
		# 1. RAW TARGET (No offset needed anymore)
		playhead_target_z = -length_per_beat * beat
		
		# 2. FEEDFORWARD FORCE
		# Calculate the speed the playhead SHOULD have (Units per Second)
		# Velocity = Dist/Beat * Beats/Sec
		# Note: This is negative because we move into negative Z
		var target_velocity = -length_per_beat * (bpm / 60.0)
		
		# We add a force exactly equal to the expected drag (Velocity * Damping)
		# This "pre-cancels" the damping, so the spring only handles position corrections
		var feedforward_force = target_velocity * damping

		# 3. STANDARD SPRING PHYSICS
		var displacement = playhead_target_z - playhead.position.z
		var spring_force = displacement * spring_strength
		var damping_force = -playhead_velocity * damping
		
		# Apply all forces
		playhead_velocity += (spring_force + damping_force + feedforward_force) * delta
		playhead.position.z = %actualplayhead.position.z

		var new_active_track = active_track
		if !mn.autoblast and input_enabled:
			if Input.is_action_just_pressed("track_next"):
				new_active_track = (active_track + 1) % trs.size()
				_switch_active_track(new_active_track)
				RenderingServer.global_shader_parameter_set("current_track", active_track)
			elif Input.is_action_just_pressed("track_prev"):
				new_active_track = (active_track - 1 + trs.size()) % trs.size()
				_switch_active_track(new_active_track)
				RenderingServer.global_shader_parameter_set("current_track", active_track)

		# Use cached measure_times reference for boundary check


func _unhandled_input(event: InputEvent) -> void:
	if manager_node.autoblast or not input_enabled:
		return

	if event.is_action_pressed("note_left")\
	or event.is_action_pressed("note_center")\
	or event.is_action_pressed("note_right"):
		var fresh_time = %Conductor.get_audio_time()
		fresh_time += (%Conductor.input_offset_ms / 1000.0)

		if event.is_action_pressed("note_left"):
			_targets[0].flash()
			_cached_active_track_node.try_blast(0, fresh_time)
		elif event.is_action_pressed("note_center"):
			_targets[1].flash()
			_cached_active_track_node.try_blast(1, fresh_time)
		elif Input.is_action_just_pressed("note_right"):
			_targets[2].flash()
			_cached_active_track_node.try_blast(2, fresh_time)

func _set_instrument_label():
	if tracks.size() > 0:
		var active_track_node = tracks[active_track] as SynRoadTrack
		instrument_label.text = SynRoadTrack.INSTRUMENTS[active_track_node.instrument][0]
		instrument_label.modulate = SynRoadTrack.INSTRUMENTS[active_track_node.instrument][1]
	
func debug_info() -> String:
	var lines: Array[String] = []
	if finished:
		lines.append("Song finished")
	else:
		lines.append("Elapsed Audio Time: %.3f" % %Conductor.time_elapsed)
		lines.append("Beat: %.4f" % %Conductor.current_beat)
		lines.append("Measure: %d : %.1f" % [%Conductor.current_measure, fmod(%Conductor.current_beat, BEATS_PER_MEASURE)])
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
			var marker_idx = track.get_measure_index_after(next_phrase_measure - 1)
			track.move_marker(marker_idx)

func _on_track_activated(note_count:int, start_measure:int):
	_inactive_safeguard_measure = start_measure # Prevents another phrase on the same measure from breaking streak
	score += note_count * min(streak, 4)
	if streak > max_streak:
		max_streak = streak
	_phrases_completed += 1
	lbl_phrase_value.hide()
	lbl_score.text = "%d" % score
	lbl_streak.text = "x%d" % min(streak,4)
	match manager_node.energy_modifier:
		0:
			# Gain 1 energy per successful phrase
			energy_change(1)
		1:
			# Gain 3 energy per successful phrase
			energy_change(3)
#	if manager_node.autoblast and current_measure < total_measures:
		# Queue up the next track to switch to on the next measure boundary
#		_autoblast_next_track = _find_best_track_for_autoblast()
#		_autoblast_track_distance = _get_phrase_distances()[_autoblast_next_track] if _autoblast_next_track != active_track else 999
#		print("Autoblast: Current track %d, queued next track %d (distance=%d)" % [active_track, _autoblast_next_track, _autoblast_track_distance])


func _on_streak_broken():
	if %Conductor.current_measure == _last_streak_break_measure:
		return  # Prevent multiple penalties in the same measure
	_last_streak_break_measure = %Conductor.current_measure
	var had_streak = streak > 0
	_miss_count += 1
	match manager_node.energy_modifier:
		0, 2:
			energy_change(-1)
			if energy <= 0:
				fail_song()
				return
		1:
			if energy <= 0:
				fail_song()
				return
		3:
			fail_song()
			return
	lbl_phrase_value.hide()
#	print("Streak break, was %d at measure %d" % [streak, current_measure])
	streak = 0
	if had_streak:
#		print("Stat updated for proper streak break.")
		_streak_breaks += 1
	lbl_streak.text = "x%d" % streak

func _on_active_phrase_missed():
	_phrases_missed += 1

func _on_inactive_phrase_missed():
	if _inactive_safeguard_measure >= %Conductor.current_measure: # this measure already had a phrase activation, do not penalize
		return

	# Enforce only one penalty per measure for inactive phrase misses
	if %Conductor.current_measure == _last_inactive_penalty_measure:
		return
		
	# If the active track is reset and there are notes in the current measure, do not penalize
	var active_track_node = tracks[active_track] as SynRoadTrack
	if active_track_node.reset_measure <= %Conductor.current_measure:
		var notes_in_measure = active_track_node.get_note_count_in_measure(%Conductor.current_measure)
		if notes_in_measure > 0:
			return
	
	_last_inactive_penalty_measure = %Conductor.current_measure
	_on_streak_broken()
	

func _switch_active_track(new_active_track:int, use_tween: bool = true):
	if new_active_track == active_track:
		return
	_cached_active_track_node = tracks[new_active_track]
#	print("Switching active track from %d to %d at beat %.2f" % [active_track, new_active_track, current_beat])
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
		_track_transition_tween.tween_property(camera, "position:x", new_x_pos, 0.15).set_trans(Tween.TRANS_SINE)
	else:
#		print("Setting camera.position.x to %f (active_track=%d, playhead.x=%f)" % [new_x_pos, active_track, playhead.position.x])
		current_track.position.x = new_x_pos
		camera.position.x = new_x_pos


func _find_best_track_for_autoblast() -> int:
	# Find closest unactivated measure using track marker_measure
	# Optimized single-pass comparison instead of multiple filter passes
	var best_track = active_track
	var best_measure_dist = 9999
	var best_note_count = -1
	var best_track_dist = 9999
	var curr_measure = %Conductor.current_measure
	
	for i in tracks.size():
		if i == active_track:
			continue
		
		var first_measure = _track_marker_measures[i]
		
		# Skip tracks with no future notes or whose phrase starts in the current measure or earlier
		if first_measure <= 0 or first_measure <= curr_measure:
			continue
		
		var measure_distance = first_measure - curr_measure
		
		# Early exit if this track is farther than our current best
		if measure_distance > best_measure_dist:
			continue
		
		# Use precomputed phrase score value as note count (already available)
		var note_count = tracks[i].phrase_score_value
		
		var track_distance = abs(i - active_track)
		
		# Compare using priority: measure_distance > note_count > track_distance > track_idx
		var is_better = false
		if measure_distance < best_measure_dist:
			is_better = true
		elif measure_distance == best_measure_dist:
			if note_count > best_note_count:
				is_better = true
			elif note_count == best_note_count:
				if track_distance < best_track_dist:
					is_better = true
				elif track_distance == best_track_dist:
					# If equidistant, prefer right (higher index)
					if i > best_track:
						is_better = true
		
		if is_better:
			best_track = i
			best_measure_dist = measure_distance
			best_note_count = note_count
			best_track_dist = track_distance
	
	return best_track

func _minimum_positive_integer_in_array(arr:Array[int]) -> int:
	var min_value = 9999
	for value in arr:
		if value > 0 and value < min_value:
			min_value = value
	return min_value

func _update_track_marker_cache(track_idx: int, marker_measure: int) -> void:
	if track_idx >= 0 and track_idx < _track_marker_measures.size():
		_track_marker_measures[track_idx] = marker_measure

func _update_track_reset_cache(track_idx: int, reset_measure: int) -> void:
	if track_idx >= 0 and track_idx < _track_reset_measures.size():
		_track_reset_measures[track_idx] = reset_measure

func energy_change(amount:int) -> void:
	energy = clampi(energy + amount, 0, MAX_ENERGY)
#	print("Energy changed by %d, new value: %d" % [amount, energy])
	if energy < 3:
		RenderingServer.global_shader_parameter_set("danger", true)
	elif energy >= 3:
		RenderingServer.global_shader_parameter_set("danger", false )
	%EnergyBar.value = energy

func _hide_fast_slow_label():
	lbl_fast_slow.hide()

func _on_note_hit(offset: float):
	_max_hit_offset = max(_max_hit_offset, offset)
	_min_hit_offset = min(_min_hit_offset, offset)
	_avg_hit_offset = ((_avg_hit_offset * _notes_hit_count) + offset) / (_notes_hit_count + 1)
	_notes_hit_count += 1
	%NotesHitLabel.text = str(_notes_hit_count)
	%EarlyHitLabel.text = str(_early_note_hits)
	%AvgHitLabel.text = "%d ms" % (_avg_hit_offset * -1000)
	%LateHitLabel.text = str(_late_note_hits)
	if abs(offset) > 0.025:
		lbl_fast_slow.show()
		if offset > 0:
			lbl_fast_slow.text = "FAST"
			_early_note_hits += 1
		else:
			lbl_fast_slow.text = "SLOW"
			_late_note_hits += 1
		
		# Reuse timer instead of creating new ones
		# SceneTreeTimer auto-disconnects on completion, so no manual disconnect needed
		if not _fast_slow_hide_timer or _fast_slow_hide_timer.time_left <= 0:
			_fast_slow_hide_timer = get_tree().create_timer(0.5)
			_fast_slow_hide_timer.timeout.connect(_hide_fast_slow_label)
	else:
		lbl_fast_slow.hide()

func fail_song():
	if _in_fail_state:
		return
	_in_fail_state = true
	manager_node.can_pause = false
	print("Song failed!")
	input_enabled = false
	var stats = {
		"score": score,
		"measure": %Conductor.current_measure,
		"max_streak": max_streak,
		"phrases_completed": _phrases_completed,
		"phrases_missed": _phrases_missed,
		"streak_breaks": _streak_breaks
	}
	%HUDAnimations.play("SongFailed")
	var slow_tween = get_tree().create_tween().set_parallel(true)
	var asps = get_tree().get_nodes_in_group("AudioPlayers")
	slow_tween.tween_property(instrument_label, "scale", Vector3.ZERO, 0.2)
	for asp in asps:
		slow_tween.tween_property(asp, "pitch_scale", 0.01, 3.0)
	await %HUDAnimations.animation_finished
	finished = true
	get_tree().call_group("AudioPlayers", "stop")
	%Conductor.is_playing = false
	song_failed.emit(stats)

func _print_new_measure_connections() -> void:
	var conns: Array = get_signal_connection_list("new_measure")
	print("--- new_measure connections (%d) ---" % conns.size())
	for conn in conns:
		var callable = conn.callable
		var target = callable.get_object()
		var method = callable.get_method()
		print(" -> %s.%s" % [target.name, method])


func _on_conductor_new_measure(measure: Variant) -> void:
	%SongProgress.value = measure
	if measure >= total_measures and !finished:
		finished = true
		%TargetPfx.emitting = true
		for tgt in _targets:
			tgt.hide()
		var results := {
			"score": score,
			"max_streak": max_streak,
			"phrases_completed": _phrases_completed,
			"phrases_missed": _phrases_missed,
			"streak_breaks": _streak_breaks,
			"perfect": _miss_count == 0,
		}
		song_finished.emit(results)
		manager_node.can_pause = false
		if not manager_node.autoblast:
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
	elif not finished:
		if _next_checkpoint < manager_node.checkpoint_measures.size():
			var checkpoint_measure = manager_node.checkpoint_measures[_next_checkpoint]
			if measure == checkpoint_measure:
				print("Reached checkpoint at measure %d" % checkpoint_measure)
				_next_checkpoint += 1
				if manager_node.energy_modifier in [0, 1] and manager_node.checkpoint_modifier == 0:
					%TargetPfx.emitting = true
					energy_change(2)  # Reward 2 energy at checkpoints for energy modifier 0
#				print("measure %d/%d" % [current_measure + 1, total_measures])
		if manager_node.energy_modifier == 1 and (manager_node.suppressed_measures[measure] == false):
			var any_unactivated = false
			for track in tracks:
				if (track as SynRoadTrack).current_measure_is_unactivated():
					any_unactivated = true
					break
			if any_unactivated:
				if energy == 0 and tracks[active_track].blasting_phrase == false:
					fail_song()
					return
				else:
					energy_change(-1)
		if lead_in_measures > 0:
			count_in.position.z = -(BEATS_PER_MEASURE * length_per_beat) * (%Conductor.current_measure + 1)
			count_in.text = str(lead_in_measures)
			if lead_in_measures == 1:
				%TargetPfx.emitting = true
				for tgt in _targets:
					tgt.show()
			lead_in_measures -= 1
		elif lead_in_measures == 0:
			lead_in_measures = -1
						
		if lead_in_measures < 1:
			# Cache active track node reference for this frame
			_cached_active_track_node = tracks[active_track] as SynRoadTrack
			
			# Check for autoblast track switching every frame
			if manager_node.autoblast and _autoblast_next_track != active_track:
				if !_cached_active_track_node.blasting_phrase:
					var next_track_node = tracks[_autoblast_next_track] as SynRoadTrack
					var switch_measure = next_track_node.phrase_start_measure
					var switch_beat = float(switch_measure - 1) * BEATS_PER_MEASURE - 0.5
					if %Conductor.current_beat >= switch_beat:
						_switch_active_track(_autoblast_next_track)
						# Update cached reference after switch
						_cached_active_track_node = tracks[active_track] as SynRoadTrack
#					print("Switching active track from %d to %d at beat %.2f" % [active_track, _autoblast_next_track, current_beat()])
	
	#lblDebugInfo.text = debug_info()
