# Benchmark System Validation Checklist

## Pre-Flight Checks

- [ ] All files created successfully:
  - [ ] `menu/benchmark_manager.gd`
  - [ ] `menu/benchmark_overlay.gd`
  - [ ] `menu/benchmark_overlay.tscn`
  - [ ] Documentation files (README, QUICKSTART, SUMMARY)

- [ ] No code compilation errors in:
  - [ ] `menu/benchmark_manager.gd` ✓
  - [ ] `menu/benchmark_overlay.gd` ✓
  - [ ] `menu/song_manager.gd` ✓
  - [ ] `entities/song.gd` ✓
  - [ ] `entities/track.gd` ✓

- [ ] Scene integration verified:
  - [ ] `benchmark_overlay` instance added to `SongManager.tscn`
  - [ ] `@onready var benchmark_overlay` wired in `song_manager.gd`

## Runtime Validation

### First Boot (SongManager.tscn, F6)

- [ ] Inspector shows Benchmark export group:
  - [ ] `Enable Benchmark` toggle (default: false)
  - [ ] `Benchmark Per Track Detail` toggle (default: false)

- [ ] With `enable_benchmark = false`:
  - [ ] Benchmark overlay is hidden
  - [ ] Song plays normally (no performance impact)

- [ ] With `enable_benchmark = true`:
  - [ ] Benchmark overlay appears in top-left corner
  - [ ] Overlay shows 12 metric labels:
    - [ ] FPS
    - [ ] Frame Time (ms)
    - [ ] Drift (ms)
    - [ ] Frame Drops
    - [ ] Active Notes
    - [ ] Active Measures
    - [ ] Chunk Loads
    - [ ] Chunk Unloads
    - [ ] Notes Spawned
    - [ ] Hit Offset (ms)
    - [ ] Notes Hit
    - [ ] Elapsed (s)
  - [ ] Metrics update each frame (FPS, Frame Time change)

### Complete Test Run

1. **Setup**:
   - [ ] Set `enable_benchmark = true`
   - [ ] Select song (e.g., Baseline)
   - [ ] Set difficulty (e.g., 96 - Beginner)
   - [ ] Configure modifiers (e.g., autoblast off, hi_speed 1.0)

2. **Play**:
   - [ ] Song initializes and starts
   - [ ] Overlay displays and updates
   - [ ] Gameplay proceeds normally
   - [ ] No hitches or lag from benchmarking overhead

3. **Completion**:
   - [ ] Song finishes or fails
   - [ ] Overlay disappears (no errors on screen)
   - [ ] No exceptions in console

4. **Data Export**:
   - [ ] `user://bench/results.csv` is created/appended
   - [ ] `user://bench/config.json` is created/updated

### CSV Validation

- [ ] Open `user://bench/results.csv` in text editor or spreadsheet:
  - [ ] Headers present: timestamp, song_uid, fps_avg, drift_max_ms, etc.
  - [ ] Exactly one data row (for single test run)
  - [ ] Values are numeric and reasonable:
    - [ ] FPS avg: 50–70 (typical 60 FPS gameplay)
    - [ ] Frame time avg: 14–20 ms (at 60 FPS)
    - [ ] Drift max: <50 ms (healthy audio sync)
    - [ ] Frame drops: 0–5 (acceptable for Beginner song)
    - [ ] Chunk loads/unloads: >0 (evidence of streaming)
    - [ ] Notes spawned: >0 (evidence of note creation)
    - [ ] Notes hit: >0 (evidence of input detection)

### Config Cache Validation

- [ ] Open `user://bench/config.json`:
  - [ ] Contains `{"per_track_detail": false, "autoblast": true, ...}`
  - [ ] Reflects last-used settings

### Per-Track Detail Mode (Optional)

- [ ] Set `benchmark_per_track_detail = true` and run another song
- [ ] CSV now includes extra columns:
  - [ ] `track_drums_active_notes_peak`
  - [ ] `track_bass_chunk_loads`
  - [ ] etc. (6 tracks × ~5 metrics)
- [ ] Per-track values are populated and reasonable

## Stress Test Scenarios

### Spaztik (High Note Density)

- [ ] Song: Spaztik, Difficulty: 114 (Expert), Autoblast: On, Hi_Speed: 1.0
- [ ] Expected overlay behavior:
  - [ ] Active Notes: 10–30+
  - [ ] Chunk Loads: 10–20 total
  - [ ] Frame Time: 15–25 ms avg
  - [ ] Drift: <5 ms avg
- [ ] CSV results reasonable and not corrupted

### The Rock Show (High BPM)

- [ ] Song: The Rock Show, Difficulty: 114, Autoblast: On, Hi_Speed: 1.0
- [ ] Expected overlay behavior:
  - [ ] Frame Time: stable 15–18 ms
  - [ ] Drift: <3 ms avg (audio sync tight)
  - [ ] Frame Drops: 0 (no stutters at high tempo)

### The Winner (Idle Droughts)

- [ ] Song: The Winner, Difficulty: 108, Autoblast: Off, Hi_Speed: 1.0
- [ ] Expected overlay behavior:
  - [ ] Chunk Unloads appear periodically (Guitar solo passages)
  - [ ] Active Notes drop to 0–2 during silence
  - [ ] No memory leaks; FPS stable

## Edge Cases

- [ ] Pause mid-song and resume:
  - [ ] Overlay remains visible
  - [ ] Metrics pause (no frame sampling during pause)
  - [ ] On resume, metrics resume (FPS updates)

- [ ] Fail song mid-play:
  - [ ] Benchmark finalizes immediately
  - [ ] CSV written with partial run data
  - [ ] `phrases_missed` count > 0

- [ ] Skip to end (instant fail export):
  - [ ] Benchmark detects failure
  - [ ] Elapsed time and measures reflect actual play

- [ ] Enable/disable benchmark without reloading scene:
  - [ ] Toggle `enable_benchmark` via inspector
  - [ ] Re-run song
  - [ ] Overlay appears/disappears correctly

## Performance Baseline

Run 5 times with same config (Baseline, Beginner, No Mods):
- [ ] FPS avg: 60 ± 2 (stable)
- [ ] Frame time avg: 16.7 ± 1 ms
- [ ] Drift max: <20 ms
- [ ] Frame drops: 0

**Expected**: Tight clustering; low variance indicates stable profiling.

## Known Limitations (Document if Found)

- [ ] CSV file grows indefinitely (cleanup recommended after testing)
- [ ] Overlay font size fixed (adjust in `BenchmarkOverlay._ready()` if needed)
- [ ] Per-track metrics only for 6 hardcoded instruments (extensible)
- [ ] No real-time graphing (manual spreadsheet analysis required)

## Documentation Review

- [ ] `BENCHMARK_README.md`:
  - [ ] Covers setup, usage, CSV schema
  - [ ] Lists metrics definitions
  - [ ] Includes test matrix recommendations

- [ ] `BENCHMARK_QUICKSTART.md`:
  - [ ] Clear 5-step instructions
  - [ ] Troubleshooting section useful
  - [ ] Test matrix presets actionable

- [ ] `IMPLEMENTATION_SUMMARY.md`:
  - [ ] Code flow diagram understandable
  - [ ] Integration points clearly documented
  - [ ] Future enhancements listed

## Sign-Off

| Check | Status | Notes |
|-------|--------|-------|
| Code compiles | ✓ | No benchmark-related errors |
| Overlay displays | ⚠️ | Pending first run |
| CSV exports | ⚠️ | Pending first run |
| Metrics accurate | ⚠️ | Pending validation |
| Documentation complete | ✓ | 3 docs created |
| Ready for testing | ⚠️ | Awaiting user validation |

---

**Next Steps**:
1. Run first benchmark test with above checklist
2. Compare CSV metrics to expected ranges
3. Validate overlay updates in real-time
4. Run stress test matrix (Spaztik, Rock Show, Winner)
5. Archive results and document findings
