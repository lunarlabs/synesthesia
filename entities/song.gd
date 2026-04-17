class_name SynRoadSong
extends Node3D

@export var energy_gradient: Gradient

const TRACK_SCENE: PackedScene = preload("res://entities/track.tscn")
const CHECKPOINT_SCENE: PackedScene = preload("res://entities/checkpoint.tscn")
const TRACK_WIDTH := 2.5
const PLAYHEAD_LEAD_DIST := 0.305
  # Tuned to minimize player hit offset
const MAX_ENERGY := 8
const STANDARD_LENGTH_PER_BEAT := 4.0
const BEATS_PER_MEASURE := 4
const ENERGY_BAR_TEXT: Dictionary = {
	0: "MOD_ENERGY_NORMAL",
	1: "MOD_ENERGY_DRAIN",
	2: "MOD_ENERGY_NORECOVER",
	3: "MOD_ENERGY_SUDDENDEATH",
	4: "MOD_ENERGY_NOFAIL",
}
const START_POSITION := Vector3(-2.0, 25.0, 5.0)
const START_ROTATION := Vector3(-50.0, -30.0, -5.0)
const GAME_POSITION := Vector3(0.0, 2.5, 2.0)
const GAME_ROTATION := Vector3(-35.0, 0.0, 0.0)
const MAX_COMBO_MULTIPLIER := 4

var energy: int = MAX_ENERGY
var manager_node: SynRoadSongManager
var bpm: float = 120.0
var seconds_per_beat: float = 0.5
var tracks: Array[Node]
var length_per_beat: float = STANDARD_LENGTH_PER_BEAT
var length_multiplier: float = 1.0
var _playhead_speed: float
var active_track := 0
var lead_in_measures := 999_999
var total_measures := 0
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
var _track_transition_tween: Tween
var _note_hit_tween: Tween
var _max_hit_offset: float = - INF
var _min_hit_offset: float = INF
var _early_note_hits: int = 0
var _late_note_hits: int = 0
var _avg_hit_offset: float = 0.0
var _notes_hit_count: int = 0
var _cached_active_track_node: SynRoadTrack # Cache active track reference
var _last_inactive_penalty_measure: int = -1 # Ensures only one energy/streak penalty per measure for inactive phrase misses
var _track_marker_measures: PackedInt32Array # Cache of marker measures for each track, updated by track._move_marker()
var closest_track_marker_measure: int = -1 # The closest track marker measure not less than the current measure
var _targets: Array
var _checkpoint_nodes: Array[Node3D]
var _next_checkpoint: int = 0
var _last_streak_break_measure: int = -1
var _barrier_threshold: int = 0 # 0 = no barrier, 2/3/4 = streak required
@onready var asp = $SongPlayer
@onready var lbl_debug_info = $DebugInfo
@onready var playhead = $Playhead
@onready var current_track = $Playhead/CurrentTrack
@onready var instrument_container = $HUD/InstrumentContainer
@onready var instrument_label = $HUD/InstrumentContainer/InstrumentLabel
@onready var camera_parent: Node3D = $Playhead/CameraParent
@onready var count_in = $CountIn
@onready var hud = $HUD
@onready var lbl_score = %ScoreLabel
@onready var lbl_streak = %StreakLabel
@onready var lbl_phrase_value = %PhraseValueLabel
@onready var lbl_auto_blast = $HUD/AutoblastLabel
@onready var lbl_fast_slow = $HUD/FastSlowLabel
@onready var fast_slow_timer = $HUD/FastSlowLabel/FastSlowTimer

signal song_prepared
signal song_failed(stats)
signal song_finished(stats)

var pv_anims: Array
var pv_pointer := 0
var lead_distance: float = 0.0
var energy_tween: Tween

func _enter_tree() -> void:
	manager_node = get_parent() as SynRoadSongManager

func _ready():
	%FadeOut.show()
	%Camera.position = START_POSITION
	%Camera.rotation_degrees = START_ROTATION
	RenderingServer.global_shader_parameter_set("danger", false)
	RenderingServer.global_shader_parameter_set("current_track", 0)
	if not manager_node.song_data:
		print("No SongData assigned, aborting")
		return
	print("Loading song: %s" % manager_node.song_data.title)
	lead_in_measures = manager_node.song_data.lead_in_measures
	length_multiplier = manager_node.length_multiplier
	total_measures = manager_node.song_data.playable_measures + lead_in_measures
	bpm = manager_node.song_data.bpm
	%Conductor.setup(asp, bpm)
	seconds_per_beat = manager_node.song_data.seconds_per_beat
	length_per_beat = STANDARD_LENGTH_PER_BEAT * length_multiplier
	_playhead_speed = - (length_per_beat / seconds_per_beat)
	lead_distance = PLAYHEAD_LEAD_DIST * length_multiplier
	_targets = [%TargetLeft, %TargetCenter, %TargetRight]
	_track_marker_measures.resize(6) # Initialize cache for 6 instrument tracks
	for i in manager_node.track_data.size():
		print("instantiating track %d" % i)
		var newTrack = TRACK_SCENE.instantiate() as SynRoadTrack
		newTrack.track_index = i
		newTrack.position.x = (TRACK_WIDTH * tracks.size())
		newTrack.instrument = manager_node.track_data[i].track_info.instrument
		newTrack.name = "Track%d" % i
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
	asp.stream = manager_node.song_data.get_audio_stream_synchronized()
	song_data_ok = true
	var checkpoint_fade_time = (seconds_per_beat * BEATS_PER_MEASURE)
	# Initialize barrier threshold before gate setup
	match manager_node.checkpoint_modifier:
		2: _barrier_threshold = 2
		3: _barrier_threshold = 3
		4: _barrier_threshold = 4
	%BarrierStreakLbl.text = "x0/x%d" % _barrier_threshold
	var start_gate = CHECKPOINT_SCENE.instantiate() as Node3D
	print("instantiating checkpoints")
	%Conductor.new_measure.connect(start_gate._on_song_new_measure)
	start_gate.get_node("Text").text = "Song Start"
	start_gate.name = "SongStart"
	start_gate.fadeout_time = checkpoint_fade_time
	start_gate.gate_location = lead_in_measures
	start_gate.position.z = - (BEATS_PER_MEASURE * length_per_beat) * lead_in_measures
	if _barrier_threshold > 0:
		# Barrier mode: show barrier appearance on start gate (streak starts at 0)
		start_gate.set_warning_state(true)
	start_gate.get_node("BoundaryLine").visible = false
	add_child(start_gate)
	var end_gate = CHECKPOINT_SCENE.instantiate() as Node3D
	%Conductor.new_measure.connect(end_gate._on_song_new_measure)
	end_gate.get_node("Text").text = "Song End"
	end_gate.name = "SongEnd"
	end_gate.fadeout_time = checkpoint_fade_time
	end_gate.gate_location = total_measures
	end_gate.position.z = - (BEATS_PER_MEASURE * length_per_beat) * total_measures
	end_gate.get_node("FinishPlane").show()
	end_gate.get_node("BoundaryLine").scale.z = 1.5
	add_child(end_gate)
	end_gate.particles.hide()
	$FinishTower.position.x = ((tracks.size() - 1) * TRACK_WIDTH) / 2
	$FinishTower.set_speed(bpm)
	$FinishTower.position.z = end_gate.position.z - 75
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
		checkpoint.get_node("BoundaryLine").visible = (manager_node.checkpoint_modifier == 0 or _barrier_threshold > 0)
		if _barrier_threshold > 0:
			checkpoint.is_barrier = true
		add_child(checkpoint)
		_checkpoint_nodes.append(checkpoint)
	if manager_node.autoblast:
		%EnergyBar.hide()
		%EnergyTitle.hide()
		%EnergyMod.show()
		%EnergyMod.text = "HUD_AUTOBLAST_ON"
	else:
		match manager_node.energy_modifier:
			1:
				energy = 5
				%EnergyBar.value = energy
			3, 4:
				#energy system disabled
				%EnergyBar.hide()
				%EnergyTitle.hide()
				%EnergyMod.show()
				%EnergyMod.text = ENERGY_BAR_TEXT[manager_node.energy_modifier]
			_:
				%EnergyBar.show()
				%EnergyBar.value = energy
	%EnergyBar.tint_progress = energy_gradient.sample(float(energy) / MAX_ENERGY)
	pv_anims = %PhraseValueAnims.get_children()
	print("Precompiling shaders...")
	for i in range(3):
		await get_tree().process_frame

	_song_start()

func _prepare_song():
	pass

func _song_start():
	print("Starting song playback.")
	playhead.position.x = ((tracks.size() - 1) * TRACK_WIDTH) / 2
	print("Playhead starting at x=%.2f" % playhead.position.x)
	current_track.position.x = (active_track * TRACK_WIDTH) - playhead.position.x
	print("Current track starting at x=%.2f" % current_track.position.x)
	camera_parent.position.x = (active_track * TRACK_WIDTH) - playhead.position.x
	print("Camera starting at x=%.2f" % camera_parent.position.x)
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
	# TODO: Replace w/ single call to synchronized audio player
	asp.play()
	%Conductor.is_playing = true
	playhead.position.z = - length_per_beat * %Conductor.current_beat
	manager_node.can_pause = true
	var _intro_anim_call := Callable(%HUDAnimations, "play").bind("BuildIn")
	var fade_tween = create_tween()
	fade_tween.tween_property(%FadeOut, "modulate", Color(1, 1, 1, 0),
	 (seconds_per_beat * BEATS_PER_MEASURE) * 1.5).set_trans(Tween.TRANS_QUAD) \
	.set_ease(Tween.EASE_IN)
	fade_tween.tween_callback(_intro_anim_call)
	var intro_tween = create_tween().set_parallel()
	intro_tween.tween_subtween(fade_tween)
	intro_tween.tween_property(%Camera, "position:x", GAME_POSITION.x, \
	2 * (seconds_per_beat * BEATS_PER_MEASURE)).set_trans(Tween.TRANS_BACK) \
	.set_ease(Tween.EASE_OUT)
	intro_tween.tween_property(%Camera, "position:y", GAME_POSITION.y, \
	2 * (seconds_per_beat * BEATS_PER_MEASURE)).set_trans(Tween.TRANS_SINE) \
	.set_ease(Tween.EASE_OUT)
	intro_tween.tween_property(%Camera, "position:z", GAME_POSITION.z, \
	2.5 * (seconds_per_beat * BEATS_PER_MEASURE)) \
	.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	intro_tween.tween_property(%Camera, "rotation_degrees", GAME_ROTATION, \
	2 * (seconds_per_beat * BEATS_PER_MEASURE)).set_trans(Tween.TRANS_BACK) \
	.set_ease(Tween.EASE_OUT)

@warning_ignore("unused_parameter")
func _process(delta: float):
	if !finished:
		if Input.is_action_just_pressed("instant_fail") and OS.is_debug_build():
			print("Instant fail triggered.")
			fail_song()
			return

		var mn = manager_node
		var trs = tracks

		# Smooth playhead movement to absorb conductor timing corrections
		var target_z = %Conductor.current_beat * -length_per_beat
		playhead.position.z = lerpf(playhead.position.z, target_z, 0.5)
		# WARN: Engaging the RenderingServer via global_shader_parameter_set every frame introduces a synchronization point that can cause CPU-GPU stalls or micro-stutters, especially if the driver queue is full.
		RenderingServer.global_shader_parameter_set("beat", %Conductor.current_beat)

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

	if event.is_action_pressed("note_left") \
	or event.is_action_pressed("note_center") \
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
	lines.append("Tracks:")
	for i in tracks.size():
		lines.append("%02d: %s" % [i, tracks[i].debug_info()])
	return "\n".join(lines)

func _on_started_phrase(phrase_score_value: int, start_measure: int, measure_count: int):
	streak += 1
	lbl_streak.text = "x%d" % min(streak, MAX_COMBO_MULTIPLIER)
	lbl_phrase_value.text = "%d" % (phrase_score_value * min(streak, MAX_COMBO_MULTIPLIER))
	lbl_phrase_value.show()
	# Tell inactive tracks to position their markers after this phrase
	var next_phrase_measure = start_measure + measure_count
	for i in tracks.size():
		if i != active_track:
			var track = tracks[i] as SynRoadTrack
			var marker_idx = track.get_measure_index_after(next_phrase_measure - 1)
			track.move_marker(marker_idx)

func _on_track_activated(note_count: int, start_measure: int):
	_inactive_safeguard_measure = start_measure # Prevents another phrase on the same measure from breaking streak
	var value = note_count * min(streak, MAX_COMBO_MULTIPLIER)
	score += value
	if streak > max_streak:
		max_streak = streak
	_phrases_completed += 1
	lbl_phrase_value.hide()
	pv_anims[pv_pointer].phrase_passed(value)
	pv_pointer = (pv_pointer + 1) % pv_anims.size()
	%HUDAnimations.play("phrase_completed")
	lbl_score.text = "%d" % score
	lbl_streak.text = "x%d" % min(streak, MAX_COMBO_MULTIPLIER)
	if _barrier_threshold > 0:
		_update_barrier_visual()
		%BarrierStreakLbl.text = "x%d/x%d" % [min(streak, MAX_COMBO_MULTIPLIER), _barrier_threshold]
		if streak >= _barrier_threshold:
			%BarrierWarningLbl.text = "HUD_BARRIER_MAINTAIN"
			%BarrierWarningLbl.remove_theme_color_override("font_color")
		else:
			%BarrierWarningLbl.text = "HUD_BARRIER_WARNING"
			%BarrierWarningLbl.add_theme_color_override("font_color", Color.ORANGE_RED)
	match manager_node.energy_modifier:
		0:
			# Gain 1 energy per successful phrase
			energy_change(1)
		1:
			# Gain 3 energy per successful phrase
			energy_change(3)
	if manager_node.autoblast and %Conductor.current_measure < total_measures:
		if _barrier_threshold > 0 \
		and _next_checkpoint < manager_node.checkpoint_measures.size():
			var checkpoint_measure = manager_node.checkpoint_measures[_next_checkpoint]
			if %Conductor.current_measure == checkpoint_measure - 1:
				# prevents "bouncing" from one track to the next while approaching gate
				return
		# Switch immediately to the next best track
		var next_track = _find_best_track_for_autoblast()
		if next_track != active_track:
			print("Autoblast: Phrase complete. Switching from %d to %d" % [active_track, next_track])
			_switch_active_track(next_track)
		else:
			print("Autoblast: Phrase complete. Staying on track %d" % active_track)


func _on_streak_broken():
	if %Conductor.current_measure == _last_streak_break_measure:
		return # Prevent multiple penalties in the same measure
	_last_streak_break_measure = %Conductor.current_measure
	var had_streak = streak > 0
	_miss_count += 1
	if lbl_phrase_value.visible:
		pv_anims[pv_pointer].phrase_failed(lbl_phrase_value.text)
		pv_pointer = (pv_pointer + 1) % pv_anims.size()
	lbl_phrase_value.hide()
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
#	print("Streak break, was %d at measure %d" % [streak, current_measure])
	streak = 0
	if _barrier_threshold > 0:
		%BarrierWarningLbl.text = "HUD_BARRIER_WARNING"
		%BarrierWarningLbl.add_theme_color_override("font_color", Color.ORANGE_RED)
		%BarrierStreakLbl.text = "x0/x%d" % _barrier_threshold
	if had_streak:
#		print("Stat updated for proper streak break.")
		%HUDAnimations.play("phrase_fail")
		_streak_breaks += 1
	lbl_streak.text = "x%d" % streak
	if _barrier_threshold > 0:
		_update_barrier_visual()

@warning_ignore("unused_parameter")
func _on_active_phrase_missed(phrase_score_value: int):
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
	

func _switch_active_track(new_active_track: int, use_tween: bool = true):
	if new_active_track == active_track:
		return
	_cached_active_track_node = tracks[new_active_track]
#	print("Switching active track from %d to %d at beat %.2f" % [active_track, new_active_track, current_beat])
#	print_stack()
	if playhead.position.x <= 0:
		print("Playhead x position is probably uninitialized (%.2f), not moving anything." % playhead.position.x)
		return
	(tracks[active_track] as SynRoadTrack).set_active(false)
	active_track = new_active_track
	(tracks[active_track] as SynRoadTrack).set_active(true)
	RenderingServer.global_shader_parameter_set("current_track", active_track)
	_set_instrument_label()
	var new_x_pos = (active_track * TRACK_WIDTH) - playhead.position.x
	if lead_in_measures >= 0:
		count_in.position.x = (active_track * TRACK_WIDTH)
	if use_tween:
		if _track_transition_tween:
			_track_transition_tween.kill()
		_track_transition_tween = get_tree().create_tween()
		_track_transition_tween.set_parallel(true)
#		print("Tweening camera.position.x to %f (active_track=%d, playhead.x=%f)" % [new_x_pos, active_track, playhead.position.x])
		_track_transition_tween.tween_property(current_track, "position:x", new_x_pos, 0.1).set_trans(Tween.TRANS_QUAD)
		_track_transition_tween.tween_property(camera_parent, "position:x", new_x_pos, 0.15).set_trans(Tween.TRANS_SINE)
	else:
#		print("Setting camera.position.x to %f (active_track=%d, playhead.x=%f)" % [new_x_pos, active_track, playhead.position.x])
		current_track.position.x = new_x_pos
		camera_parent.position.x = new_x_pos


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

func _minimum_positive_integer_in_array(arr: Array[int]) -> int:
	var min_value = 9999
	for value in arr:
		if value > 0 and value < min_value:
			min_value = value
	return min_value

func _update_track_marker_cache(track_idx: int, marker_measure: int) -> void:
	if track_idx >= 0 and track_idx < _track_marker_measures.size():
		_track_marker_measures[track_idx] = marker_measure
		_update_closest_track_marker_cache()

func _update_closest_track_marker_cache() -> void:
	var candidates: Array[int] = []
	var curr_measure = %Conductor.current_measure
	
	for i in tracks.size():
		var m = _track_marker_measures[i]
		if m < 0:
			continue

		var t = tracks[i]
		# Criteria:
		# If NOT blasting: visible on Current or Ahead (>= curr)
		# If blasting: visible only on Ahead (> curr)
		if (not t.blasting_phrase and m >= curr_measure) \
		or (t.blasting_phrase and m > curr_measure):
			candidates.append(m)

	if candidates.size() > 0:
		closest_track_marker_measure = candidates.min()
	else:
		closest_track_marker_measure = -1
		
	for track in tracks:
		var should_be_visible = (manager_node.hide_streak_hints == false) \
			and (closest_track_marker_measure != -1) \
			and (track.marker_measure() == closest_track_marker_measure)
			
		# Enforce Ahead-only rule for blasting tracks
		if track.blasting_phrase and track.marker_measure() <= curr_measure:
			should_be_visible = false
			
		track.marker.visible = should_be_visible

func _update_track_reset_cache(_track_idx: int, _reset_measure: int) -> void:
	pass

func energy_change(amount: int) -> void:
	energy = clampi(energy + amount, 0, MAX_ENERGY)
#	print("Energy changed by %d, new value: %d" % [amount, energy])
	if energy < 3:
		RenderingServer.global_shader_parameter_set("danger", true)
	elif energy >= 3:
		RenderingServer.global_shader_parameter_set("danger", false)
	%EnergyBar.value = energy
	if energy_tween:
		energy_tween.kill()
	energy_tween = create_tween()
	match sign(amount):
		1:
			%EnergyBar.tint_progress = Color.WHITE
			energy_tween.tween_property(%EnergyBar, "tint_progress", energy_gradient.sample(float(energy) / MAX_ENERGY), 0.5)
		-1:
			if manager_node.energy_modifier == 1:
				energy_tween.tween_property(%EnergyBar, "tint_progress", energy_gradient.sample(float(energy) / MAX_ENERGY), 0.5)
			else:
				%EnergyBar.tint_under = Color(3.0, 1.5, 0.0)
				energy_tween.tween_property(%EnergyBar, "tint_under", Color.WHITE, 0.5)
				%EnergyBar.tint_progress = energy_gradient.sample(float(energy) / MAX_ENERGY)
		_:
			print("Zero provided to energy_change()")
	

func _hide_fast_slow_label():
	lbl_fast_slow.remove_theme_color_override("font_color")
	lbl_fast_slow.text = ""

func _on_note_hit(offset: float):
	if _note_hit_tween:
		_note_hit_tween.kill()
	_note_hit_tween = create_tween()
	lbl_phrase_value.scale = Vector2(1.25, 1.25)
	_note_hit_tween.tween_property(lbl_phrase_value, "scale", Vector2(1.0, 1.0), 0.1)
	_max_hit_offset = max(_max_hit_offset, offset)
	_min_hit_offset = min(_min_hit_offset, offset)
	_avg_hit_offset = ((_avg_hit_offset * _notes_hit_count) + offset) / (_notes_hit_count + 1)
	_notes_hit_count += 1
	%NotesHitLabel.text = str(_notes_hit_count)
	%EarlyHitLabel.text = str(_early_note_hits)
	%AvgHitLabel.text = "%d ms" % (_avg_hit_offset * -1000)
	%LateHitLabel.text = str(_late_note_hits)
	if abs(offset) > 0.015:
		lbl_fast_slow.show()
		if offset > 0:
			lbl_fast_slow.add_theme_color_override("font_color", Color.LIGHT_CORAL)
			lbl_fast_slow.text = "FAST"
			_early_note_hits += 1
		else:
			lbl_fast_slow.add_theme_color_override("font_color", Color.LIGHT_BLUE)
			lbl_fast_slow.text = "SLOW"
			_late_note_hits += 1
		fast_slow_timer.start(0.5)
	else:
		fast_slow_timer.stop()
		_hide_fast_slow_label()

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
	slow_tween.tween_property(instrument_container, "scale", Vector2.ZERO, 0.5)
	slow_tween.tween_property(asp, "pitch_scale", 0.01, 3.0)
	await %HUDAnimations.animation_finished
	finished = true
	asp.stop()
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

func change_track_volume(track_idx: int, volume: float) -> void:
	var stream = asp.stream as AudioStreamSynchronized
	var channel := track_idx + 1
	clampf(volume, -60., 0.)
	stream.set_sync_stream_volume(channel, volume)

func get_track_volume(track_idx: int) -> float:
	var stream = asp.stream as AudioStreamSynchronized
	var channel := track_idx + 1
	return stream.get_sync_stream_volume(channel)

func _on_conductor_new_measure(measure: Variant) -> void:
	%SongProgress.value = measure
	if measure >= total_measures and !finished:
		finished = true
		%Conductor.vibration = false
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
		tween.tween_property(camera_parent, "position:x", 0.0, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(%Camera, "position:y", 3.0, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		var stop_duration = seconds_per_beat * BEATS_PER_MEASURE * 2
		# To match initial velocity (play speed) with a Quad EaseOut, Distance must be V0 * T / 2
		# V0 = length/sec. T = 2 * measures_sec.
		# D = (len/sec) * (2 * beats * sec) / 2 = len * beats = 1 measure length
		var stop_distance = length_per_beat * BEATS_PER_MEASURE
		tween.tween_property(%Camera, "position:z", %Camera.position.z - stop_distance, stop_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(%Camera, "rotation_degrees:x", 0.0, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(instrument_container, "scale", Vector2.ZERO, 0.2)
		for i in tracks.size():
			asp.stream.set_sync_stream_volume(i + 1, -6.0)
		playhead.position.z = - (BEATS_PER_MEASURE * length_per_beat) * total_measures
		var _phrase_capture_accuracy = float(_phrases_completed * 100) / (_phrases_completed + _phrases_missed)
		print("Song finished!")
	elif not finished:
		_update_closest_track_marker_cache()
		if _next_checkpoint < manager_node.checkpoint_measures.size():
			var checkpoint_measure = manager_node.checkpoint_measures[_next_checkpoint]
			if measure == checkpoint_measure:
				print("Reached checkpoint at measure %d" % checkpoint_measure)
				_next_checkpoint += 1
				if _barrier_threshold > 0:
					_process_barrier_crossing()
				elif manager_node.checkpoint_modifier == 0:
					if manager_node.energy_modifier in [0, 1]:
						%TargetPfx.emitting = true
						energy_change(2) # Reward 2 energy at checkpoints for energy modifier 0
			elif _barrier_threshold > 0 and measure == checkpoint_measure - 10: # Start of warning zone
				%BarrierWarningContainer.show()
				for i in tracks.size():
					change_track_volume(i, -6.0)
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
			count_in.position.z = - (BEATS_PER_MEASURE * length_per_beat) * (%Conductor.current_measure + 1)
			count_in.text = str(lead_in_measures)
			if lead_in_measures == 2:
				var tween = create_tween()
				tween.tween_property(instrument_container, "scale", Vector2.ONE, 0.2)
				%TargetPfx.emitting = true
				for tgt in _targets:
					tgt.show()
			lead_in_measures -= 1
		elif lead_in_measures == 0:
			lead_in_measures = -1
			if _barrier_threshold > 0:
				_process_barrier_crossing() # Start gate barrier (always fails, streak = 0)
						
		if lead_in_measures < 1:
			# Cache active track node reference for this frame
			_cached_active_track_node = tracks[active_track] as SynRoadTrack
			

	#lblDebugInfo.text = debug_info()

func _process_barrier_crossing() -> void:
	if streak >= _barrier_threshold:
		# SUCCESS — energy bonus + restore cached activations on all tracks
		print("Barrier crossed successfully (streak %d >= %d)" % [streak, _barrier_threshold])
		%TargetPfx.emitting = true
		energy_change(2)
		for track in tracks:
			var t = track as SynRoadTrack
			if t.last_activated_phrase_idx >= 0:
				t.restore_barrier_activation(t.last_activated_phrase_idx)
		_show_barrier_message("HUD_BARRIER_SUCCESS")
		for i in tracks.size():
			change_track_volume(i, -6.0)
		if manager_node.autoblast:
			# Since there's activations after the barrier, we need to update the active track
			var next_track = _find_best_track_for_autoblast()
			if next_track != active_track:
				print("Autoblast: Updating active track from %d to %d" % [active_track, next_track])
				_switch_active_track(next_track)
			else:
				print("Autoblast: Staying on track %d" % active_track)
	else:
		# FAILURE — energy penalty, tracks stay reset at C+2
		print("Barrier failed (streak %d < %d)" % [streak, _barrier_threshold])
		_apply_barrier_penalty()
		_show_barrier_message("HUD_BARRIER_FAILED")

func _apply_barrier_penalty() -> void:
	if energy >= 6:
		energy_change(-4)
	elif energy > 2:
		var penalty = - (energy - 2)
		energy_change(penalty)
	# else: energy <= 2, no damage
	
	if energy <= 0:
		fail_song()

func _update_barrier_visual() -> void:
	# TODO: Find out what the next checkpoint is instead of using the start gate
	if _next_checkpoint < manager_node.checkpoint_measures.size():
		var barrier = _checkpoint_nodes[_next_checkpoint]
		var below_threshold = streak < _barrier_threshold
		barrier.set_warning_state(below_threshold)
	# Update barrier warning message based on streak vs threshold

func _show_barrier_message(message_key: String) -> void:
	%BarrierWarningLbl.text = message_key
	%BarrierWarningContainer.show()
	# Auto-hide after a delay
	var timer = get_tree().create_timer(2.0)
	timer.timeout.connect(%BarrierWarningContainer.hide)
