# Synesthesia Road Performance Benchmark System

A comprehensive benchmark overlay and metrics collector for profiling Synesthesia Road performance across different songs, difficulties, and modifiers.

## Features

### Real-Time Overlay Display
- **FPS & Frame Timing**: Current FPS and frame time (ms) with P95 percentile tracking
- **Audio Drift**: Drift statistics (avg, max) and frame drop counts
- **Rendering**: Active note/measure counts, peak values during run
- **Streaming**: Chunk load/unload counts, total notes spawned
- **Gameplay**: Hit accuracy (offset in ms), notes hit count, elapsed time

### Per-Run Data Collection
Each run captures:
- Song metadata (UID, name, difficulty)
- Modifier settings (autoblast, hi_speed, timing/energy mods)
- Performance metrics (FPS avg/min/max, frame time p95, drift stats)
- Rendering/streaming events (chunk loads/unloads, notes spawned)
- Gameplay accuracy (hit offsets, notes hit, streaks, score)
- Track state (optional per-track metrics when enabled)

### Data Persistence
- Results saved to `user://bench/results.csv` in append mode
- Config cached in `user://bench/config.json` (last-used settings)
- Human-readable timestamps and indexed by song UID

## Usage

### Enable Benchmarking

In the Godot inspector (or via script), set exports on `SongManager.tscn`:
```gdscript
enable_benchmark = true
benchmark_per_track_detail = false  # (optional) show detailed per-track columns
```

The overlay will appear in the top-left during gameplay once enabled.

### CSV Output Format

**File:** `user://bench/results.csv`

**Global Columns** (always included):
- `timestamp`, `song_uid`, `song_name`, `difficulty`
- `autoblast`, `hi_speed`, `timing_modifier`, `energy_modifier`
- `fps_avg`, `fps_min`, `fps_max`, `frame_time_avg_ms`, `frame_time_p95_ms`
- `drift_avg_ms`, `drift_max_ms`, `drift_samples`, `frame_drops`
- `active_notes_peak`, `active_measures_peak`
- `chunk_loads_total`, `chunk_unloads_total`, `notes_spawned_total`
- `hit_offset_avg_ms`, `hit_offset_min_ms`, `hit_offset_max_ms`, `notes_hit_count`
- `score`, `max_streak`, `phrases_completed`, `phrases_missed`, `streak_breaks`, `miss_count`

**Per-Track Columns** (when `benchmark_per_track_detail = true`):
- For each track (DRUMS, BASS, GUITAR, SYNTH, VOCALS, FX):
  - `track_{name}_active_notes_peak`
  - `track_{name}_active_measures_peak`
  - `track_{name}_chunk_loads`, `chunk_unloads`, `notes_spawned`

### Test Matrix Presets

Recommended runs for profiling:

| Song           | Difficulty | Autoblast | Hi_Speed | Notes                          |
|---|---|---|---|---|
| Spaztik        | 114 (Expert)| On        | 1.0, 1.5, 2.0 | Max note density, streaming stress |
| The Rock Show  | 114        | On        | 1.0, 1.5     | Fastest BPM, audio sync drift    |
| The Winner     | 108 (Adv)  | Off       | 1.0          | Long droughts, chunk unload test |
| Baseline       | 96 (Begin) | Off       | 1.0          | Baseline density, sanity check   |
| Out the Box    | 114        | On        | 1.0          | Medium density comparison        |

## Architecture

### Components

1. **BenchmarkManager** (`menu/benchmark_manager.gd`)
   - Central metrics aggregator
   - Per-run accumulation of frame, measure, and track data
   - CSV export with configurable schema
   - Config persistence (user://)

2. **BenchmarkOverlay** (`menu/benchmark_overlay.gd` / `benchmark_overlay.tscn`)
   - Real-time display panel in top-left
   - Updated each frame with current metrics
   - Toggleable via `enable_benchmark` export in `SongManager`

3. **Instrumentation Points**
   - `SynRoadSongManager._process()`: Samples FPS, frame time; aggregates track metrics; updates overlay
   - `SynRoadSong._ready()`: Connects benchmark manager to `new_measure` signal for per-measure tracking
   - `SynRoadSong._on_note_hit()`: Already tracks hit offsets (benchmark reads this)
   - `SynRoadTrack.benchmark_chunk_loads`, `benchmark_chunk_unloads`, `benchmark_notes_spawned`: Counters incremented during chunk load/unload
   - `MeasureChunk.load_if_needed()`, `unload()`: Emit load/unload events

### Data Flow

```
Song Frame Loop
  ├─> SongManager._process()
  │    ├─> Sample FPS, delta → BenchmarkManager
  │    └─> Read SynRoadSong/SynRoadTrack metrics → Overlay.update_metrics()
  │
  └─> SynRoadSong._process()
       ├─> Emit new_measure(measure_num)
       │    └─> BenchmarkManager.sample_measure()
       │
       ├─> Track.load_if_needed() → increment benchmark_chunk_loads
       │
       ├─> Track.unload() → increment benchmark_chunk_unloads
       │
       └─> note_hit(offset) → update _avg_hit_offset, _notes_hit_count

Song End
  └─> _on_song_failed() or _on_song_finished()
       └─> BenchmarkManager.finalize_run(song_node)
            └─> Compute averages, P95, peaks
            └─> Write to user://bench/results.csv
```

## Metrics Definitions

- **FPS avg/min/max**: Sampled via `Engine.get_frames_per_second()` every frame
- **Frame time p95**: 95th percentile of frame times across run (milliseconds)
- **Drift**: Audio playhead vs. logical beat clock; `max_drift` and rolling average
- **Frame drops**: Counter incremented in `SynRoadSong` when `abs(drift) > 0.05s`
- **Active nodes peak**: Highest count of loaded notes/measures during run
- **Chunk events**: Load/unload counters per track (sums to global totals)
- **Notes spawned**: Total notes instantiated in all chunks during run
- **Hit offset**: Time between note tap and visual target; avg/min/max in milliseconds

## Configuration

### User Directory

Results and config stored in `user://bench/`:
```
user://bench/
  ├─ results.csv          (appended per run)
  └─ config.json          (last-used settings)
```

Retrieve via:
```gdscript
# Check results
FileAccess.open("user://bench/results.csv", FileAccess.READ)

# Load last config
var config_str = FileAccess.get_file_as_string("user://bench/config.json")
var config = JSON.parse_string(config_str)
```

### Modifying Metrics

To add new metrics:
1. Update `BenchmarkManager.finalize_run()` to compute/read from `song_node`
2. Add column header to `_save_run_to_csv()` `headers` array
3. Update row assignment in `_save_run_to_csv()` 
4. (Optional) Add label to `BenchmarkOverlay.labels` dict and update display in `update_metrics()`

## Example: Manual Benchmark Run

```gdscript
# In SongManager inspector, set:
enable_benchmark = true
song_file = "uid://cmv7jola8rpbe"  # Spaztik
difficulty = 114  # Expert
autoblast = true
hi_speed = 1.0

# Play the song. Overlay will display live metrics.
# On completion, user://bench/results.csv is appended with run data.
```

## Limitations

- Per-track metrics optional (appends many columns); disabled by default for readability
- Overlay positioned fixed at top-left; adjust in `BenchmarkOverlay._ready()` if needed
- CSV append-only; manual cleanup of old runs recommended periodically
- Frame sampling happens in `_process()`, so frame time includes benchmark sampling overhead (negligible)

## Future Enhancements

- JSON logs with per-measure snapshots for deeper analysis
- Automated test matrix runner (loop over presets)
- Visualization tool (matplotlib/spreadsheet import)
- Per-phrase accuracy breakdown
- Chunk streaming timeline visualization (which chunks load/unload when)

---

**Created:** December 2024  
**For:** Synesthesia Road (Godot 4.5, GDScript)
