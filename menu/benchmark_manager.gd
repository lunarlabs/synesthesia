extends Node
class_name BenchmarkManager

## Global benchmark metrics aggregator
## Samples per-frame and per-measure metrics, persists to user://bench/

var is_enabled: bool = false
var show_per_track_detail: bool = false
var autoblast_default: bool = true

# Per-run accumulation
var run_metrics: Dictionary = {}
var frame_samples: Array[float] = []
var frame_times_ms: Array[float] = []

# Per-track accumulation (indexed by instrument name)
var track_metrics: Dictionary = {}

# Config persistence
var config_path: String = "user://bench/config.json"
var results_path: String = "user://bench/results.csv"

signal run_completed(results: Dictionary)

func _ready() -> void:
	# Ensure benchmark directory exists
	var bench_dir = "user://bench"
	if not DirAccess.dir_exists_absolute(bench_dir):
		var dir = DirAccess.open("user://")
		if dir:
			dir.make_dir("bench")
	_load_config()

func _load_config() -> void:
	if ResourceLoader.exists(config_path):
		var config_file = JSON.parse_string(FileAccess.get_file_as_string(config_path))
		if config_file:
			show_per_track_detail = config_file.get("per_track_detail", false)
			autoblast_default = config_file.get("autoblast", true)

func _save_config() -> void:
	var config = {
		"per_track_detail": show_per_track_detail,
		"autoblast": autoblast_default,
		"timestamp": Time.get_ticks_msec()
	}
	var json_str = JSON.stringify(config)
	var file = FileAccess.open(config_path, FileAccess.WRITE)
	if file:
		file.store_string(json_str)

func start_run(song_data: SongData, difficulty: int, modifiers: Dictionary) -> void:
	is_enabled = true
	run_metrics.clear()
	frame_samples.clear()
	frame_times_ms.clear()
	track_metrics.clear()
	
	run_metrics["timestamp"] = Time.get_ticks_msec()
	run_metrics["timestamp_str"] = Time.get_datetime_string_from_system()
	run_metrics["song_uid"] = song_data.resource_path if song_data.resource_path else "unknown"
	run_metrics["song_name"] = song_data.title
	run_metrics["difficulty"] = difficulty
	run_metrics["autoblast"] = modifiers.get("autoblast", autoblast_default)
	run_metrics["hi_speed"] = modifiers.get("hi_speed", 1.0)
	run_metrics["timing_modifier"] = modifiers.get("timing_modifier", 0)
	run_metrics["energy_modifier"] = modifiers.get("energy_modifier", 0)
	
	# Initialize per-track dicts for all instruments
	var instrument_names = ["DRUMS", "BASS", "GUITAR", "SYNTH", "VOCALS", "FX"]
	for instrument_name in instrument_names:
		track_metrics[instrument_name] = {
			"active_notes_peak": 0,
			"active_measures_peak": 0,
			"chunk_loads": 0,
			"chunk_unloads": 0,
			"notes_spawned": 0,
			"phrases_started": 0,
			"phrases_completed": 0,
			"phrases_missed": 0,
			"volume_blasting": 0,
			"volume_unfocused": 0,
			"volume_muted": 0
		}

func sample_frame(delta: float, fps: float) -> void:
	if not is_enabled:
		return
	frame_samples.append(fps)
	frame_times_ms.append(delta * 1000.0)

func sample_measure(measure_num: int) -> void:
	if not is_enabled:
		return
	
	# Update global metrics
	if not "measures_played" in run_metrics:
		run_metrics["measures_played"] = 0
	run_metrics["measures_played"] = measure_num

func finalize_run(song_node: SynRoadSong) -> void:
	if not is_enabled:
		return
	is_enabled = false
	
	# Compute derived metrics
	run_metrics["elapsed_sec"] = song_node.time_elapsed
	run_metrics["frame_drops"] = song_node.frame_drops
	run_metrics["drift_avg_ms"] = (song_node.total_drift / max(song_node.drift_samples, 1)) * 1000.0
	run_metrics["drift_max_ms"] = song_node.max_drift * 1000.0
	run_metrics["drift_samples"] = song_node.drift_samples
	
	# Hit accuracy
	run_metrics["hit_offset_avg_ms"] = song_node._avg_hit_offset * 1000.0 if not is_nan(song_node._avg_hit_offset) else 0.0
	run_metrics["hit_offset_min_ms"] = song_node._min_hit_offset * 1000.0 if not is_nan(song_node._min_hit_offset) else 0.0
	run_metrics["hit_offset_max_ms"] = song_node._max_hit_offset * 1000.0 if not is_nan(song_node._max_hit_offset) else 0.0
	run_metrics["notes_hit_count"] = song_node._notes_hit_count
	
	# FPS stats
	if frame_samples.size() > 0:
		run_metrics["fps_avg"] = frame_samples.reduce(func(a, b): return a + b) / frame_samples.size()
		run_metrics["fps_min"] = frame_samples.min()
		run_metrics["fps_max"] = frame_samples.max()
	if frame_times_ms.size() > 0:
		frame_times_ms.sort()
		run_metrics["frame_time_avg_ms"] = frame_times_ms.reduce(func(a, b): return a + b) / frame_times_ms.size()
		var p95_idx = int(frame_times_ms.size() * 0.95)
		run_metrics["frame_time_p95_ms"] = frame_times_ms[p95_idx]
	
	# Global rendering/streaming
	var total_active_notes = 0
	var total_active_measures = 0
	var total_chunk_loads = 0
	var total_chunk_unloads = 0
	var total_notes_spawned = 0
	
	for track in song_node.tracks:
		if track is SynRoadTrack:
			total_active_notes += track.note_nodes.size()
			total_active_measures += track.measure_nodes.size()
			if "benchmark_chunk_loads" in track:
				total_chunk_loads += track.benchmark_chunk_loads
			if "benchmark_chunk_unloads" in track:
				total_chunk_unloads += track.benchmark_chunk_unloads
			if "benchmark_notes_spawned" in track:
				total_notes_spawned += track.benchmark_notes_spawned
	
	run_metrics["active_notes_peak"] = total_active_notes
	run_metrics["active_measures_peak"] = total_active_measures
	run_metrics["chunk_loads_total"] = total_chunk_loads
	run_metrics["chunk_unloads_total"] = total_chunk_unloads
	run_metrics["notes_spawned_total"] = total_notes_spawned
	
	# Score/streak/gameplay
	run_metrics["score"] = song_node.score
	run_metrics["max_streak"] = song_node.max_streak
	run_metrics["phrases_completed"] = song_node._phrases_completed
	run_metrics["phrases_missed"] = song_node._phrases_missed
	run_metrics["streak_breaks"] = song_node._streak_breaks
	run_metrics["miss_count"] = song_node._miss_count
	
	emit_signal("run_completed", run_metrics)
	_save_run_to_csv()
	_save_config()

func _save_run_to_csv() -> void:
	var headers: Array[String] = [
		"timestamp", "song_uid", "song_name", "difficulty", 
		"autoblast", "hi_speed", "timing_modifier", "energy_modifier",
		"elapsed_sec", "measures_played",
		"fps_avg", "fps_min", "fps_max", "frame_time_avg_ms", "frame_time_p95_ms",
		"drift_avg_ms", "drift_max_ms", "drift_samples", "frame_drops",
		"active_notes_peak", "active_measures_peak",
		"chunk_loads_total", "chunk_unloads_total", "notes_spawned_total",
		"hit_offset_avg_ms", "hit_offset_min_ms", "hit_offset_max_ms", "notes_hit_count",
		"score", "max_streak", "phrases_completed", "phrases_missed", "streak_breaks", "miss_count"
	]
	
	# Add per-track columns if enabled
	var per_track_headers: Array[String] = []
	if show_per_track_detail:
		for track_name in track_metrics.keys():
			per_track_headers.append("track_%s_active_notes_peak" % track_name.to_lower())
			per_track_headers.append("track_%s_active_measures_peak" % track_name.to_lower())
			per_track_headers.append("track_%s_chunk_loads" % track_name.to_lower())
			per_track_headers.append("track_%s_chunk_unloads" % track_name.to_lower())
			per_track_headers.append("track_%s_notes_spawned" % track_name.to_lower())
	
	headers.append_array(per_track_headers)
	
	# Build row
	var row: Array[String] = []
	for header in headers:
		if "_" in header and header.begins_with("track_"):
			# Per-track column
			var parts = header.split("_")
			var track_name = parts[1].to_upper()
			var metric = "_".join(parts.slice(2))
			row.append(str(track_metrics.get(track_name, {}).get(metric, 0)))
		else:
			row.append(str(run_metrics.get(header, "")))
	
	# Append to CSV using simple file operations
	var check_file = FileAccess.open(results_path, FileAccess.READ)
	var file_exists = check_file != null
	if check_file:
		check_file = null
	
	if not file_exists:
		# Create new file with headers
		var new_file = FileAccess.open(results_path, FileAccess.WRITE)
		if new_file:
			new_file.store_csv_line(headers)
			new_file.store_csv_line(row)
	else:
		# Append to existing file
		var append_file = FileAccess.open(results_path, FileAccess.WRITE)
		if append_file:
			append_file.seek_end()
			append_file.store_csv_line(row)

func update_track_metric(track_name: String, metric: String, value: int) -> void:
	if not is_enabled or not track_name in track_metrics:
		return
	if metric in track_metrics[track_name]:
		track_metrics[track_name][metric] = value

func increment_track_metric(track_name: String, metric: String) -> void:
	if not is_enabled or not track_name in track_metrics:
		return
	if metric in track_metrics[track_name]:
		track_metrics[track_name][metric] += 1
