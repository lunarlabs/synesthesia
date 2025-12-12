extends PanelContainer
class_name BenchmarkOverlay

## Real-time benchmark metrics display overlay

@onready var vbox = VBoxContainer.new()
var labels: Dictionary = {}
var benchmark_manager: BenchmarkManager

func _ready() -> void:
	# Setup panel
	add_child(vbox)
#	vbox.separation = 2
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.3
	anchor_bottom = 0.5
	offset_left = 5
	offset_top = 5
	offset_right = -5
	offset_bottom = -5
	
	# Create labels for each metric
	var metric_keys = [
		"FPS", "Frame Time (ms)", "Drift (ms)", "Frame Drops",
		"Active Notes", "Active Measures", 
		"Chunk Loads", "Chunk Unloads", "Notes Spawned",
		"Hit Offset (ms)", "Notes Hit", "Elapsed (s)"
	]
	
	for key in metric_keys:
		var label = Label.new()
		label.text = "%s: --" % key
		label.add_theme_font_size_override("font_size", 10)
		vbox.add_child(label)
		labels[key] = label

func update_metrics(metrics: Dictionary) -> void:
	if not is_node_ready():
		return
	
	var fps = metrics.get("fps", 0.0)
	var frame_time_ms = metrics.get("frame_time_ms", 0.0)
	var drift_ms = metrics.get("drift_ms", 0.0)
	var frame_drops = metrics.get("frame_drops", 0)
	var active_notes = metrics.get("active_notes", 0)
	var active_measures = metrics.get("active_measures", 0)
	var chunk_loads = metrics.get("chunk_loads", 0)
	var chunk_unloads = metrics.get("chunk_unloads", 0)
	var notes_spawned = metrics.get("notes_spawned", 0)
	var hit_offset_ms = metrics.get("hit_offset_ms", 0.0)
	var notes_hit = metrics.get("notes_hit", 0)
	var elapsed = metrics.get("elapsed", 0.0)
	
	labels["FPS"].text = "FPS: %.1f" % fps
	labels["Frame Time (ms)"].text = "Frame Time (ms): %.2f" % frame_time_ms
	labels["Drift (ms)"].text = "Drift (ms): %.2f" % drift_ms
	labels["Frame Drops"].text = "Frame Drops: %d" % frame_drops
	labels["Active Notes"].text = "Active Notes: %d" % active_notes
	labels["Active Measures"].text = "Active Measures: %d" % active_measures
	labels["Chunk Loads"].text = "Chunk Loads: %d" % chunk_loads
	labels["Chunk Unloads"].text = "Chunk Unloads: %d" % chunk_unloads
	labels["Notes Spawned"].text = "Notes Spawned: %d" % notes_spawned
	labels["Hit Offset (ms)"].text = "Hit Offset (ms): %.2f" % hit_offset_ms
	labels["Notes Hit"].text = "Notes Hit: %d" % notes_hit
	labels["Elapsed (s)"].text = "Elapsed (s): %.1f" % elapsed
