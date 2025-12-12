# Quick Start: Benchmark Scene Setup

## Files Created/Modified

### New Files
- `menu/benchmark_manager.gd` — Core metrics aggregator and CSV persistence
- `menu/benchmark_overlay.gd` — Real-time overlay display
- `menu/benchmark_overlay.tscn` — Overlay scene
- `BENCHMARK_README.md` — Comprehensive documentation

### Modified Files
- `menu/song_manager.gd` — Added benchmark integration, frame sampling, overlay wiring
- `menu/SongManager.tscn` — Added benchmark overlay instance
- `entities/song.gd` — Connected benchmark manager to `new_measure` signal
- `entities/track.gd` — Added chunk/note tracking counters

## Enable Benchmarking

1. Open `menu/SongManager.tscn` in Godot editor
2. Select the "SongManager" node
3. In the Inspector, expand the **Benchmark** export group:
   - Set `Enable Benchmark` to **true**
   - (Optional) Set `Benchmark Per Track Detail` to **true** for detailed per-instrument columns
4. Save and run the scene (`F6`)

The overlay will appear in the top-left corner during gameplay.

## Run a Benchmark

With `enable_benchmark = true`:
1. Configure your test case:
   - Select song via `Song File` export
   - Set `Difficulty` (Beginner/Intermediate/Advanced/Expert)
   - Toggle modifiers: `Autoblast`, `Hi Speed`, `Timing Modifier`, `Energy Modifier`
2. Press Play/F6 to start the song
3. Play through the entire song (or let it fail/complete)
4. On song end, metrics are automatically written to `user://bench/results.csv`

## Review Results

Check results at:
```
%APPDATA%/Godot/app_userdata/synesthesia/bench/results.csv
```
(Windows) or equivalent user directory on macOS/Linux.

Open in any spreadsheet editor (Excel, Google Sheets, LibreOffice) to analyze:
- FPS averages, frame time percentiles
- Drift and frame drop counts
- Chunk load/unload frequencies
- Hit accuracy (offset, notes hit count)
- Per-run modifiers and settings

## Test Matrix Recommendations

For comprehensive profiling, run these combinations:

### Baseline (Sanity Check)
- **Baseline** difficulty Beginner, autoblast off, hi_speed 1.0
- Expected: 60+ FPS, minimal frame drops, <10ms avg drift

### Streaming Stress
- **Spaztik** difficulty Expert, autoblast on, hi_speed 1.0/1.5/2.0
- Expected: FPS drop as hi_speed increases; monitor chunk loads/unloads

### Timing Extremes
- **The Rock Show** difficulty Expert, autoblast on, hi_speed 1.0
- Expected: Low audio drift (<5ms avg), consistent FPS

### Idle Behavior
- **The Winner** difficulty Advanced, autoblast off, hi_speed 1.0
- Expected: Stable chunk unload/reload cycles on Guitar solo passages

## Config Persistence

After each run, `user://bench/config.json` caches:
- Last-used `autoblast` setting
- `per_track_detail` toggle state

This allows quick re-runs with the same modifiers.

## Troubleshooting

### Overlay not showing?
- Verify `enable_benchmark = true` in SongManager inspector
- Check that `benchmark_overlay` is visible in the node tree

### No CSV file created?
- Ensure benchmark_manager has been initialized in `_ready()`
- Check user:// directory permissions
- Verify song completed or failed (not paused/quit mid-song)

### Metrics seem wrong?
- Frame time includes UI overhead; isolate rendering by disabling overlay temporarily
- Drift spikes can occur during shader compilation; do a "warm-up" run first
- Per-track metrics only populated if `benchmark_per_track_detail = true`

## Next Steps

1. Run a full test matrix across target songs
2. Export CSV to spreadsheet for analysis
3. Identify performance bottlenecks:
   - High frame drops → check chunk streaming, visibility range
   - Increasing frame time at hi_speed → spatial density issue
   - Chunk load/unload spikes → adjust `CHUNK_LOAD_RANGE_FORWARD` in `track.gd`
4. Profile with Godot's built-in profiler (`F6` → Profile tab) for deeper insight into hot functions

---

See `BENCHMARK_README.md` for full documentation.
