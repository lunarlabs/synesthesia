# Synesthesia Road - AI Agent Instructions

## Project Overview
Synesthesia Road is a rhythm game built in Godot 4.5 using GDScript. Players activate musical tracks by hitting notes in time with the music, switching between 6 instrument tracks (Drums, Bass, Guitar, Synth, Vocals, FX) to build scores and maintain streaks.

## Core Architecture

### Entity Hierarchy
- **SynRoadSong** (`entities/song.gd`) - Main conductor orchestrating all gameplay
  - Manages time, measures, input handling, scoring, and track switching
  - Instantiates tracks dynamically from `SongData` resource
  - Drives the gameplay loop in `_process()` with beat/measure calculations
- **SynRoadTrack** (`entities/track.gd`) - Individual instrument track (6 per song)
  - Handles note hit detection via `try_blast(lane_index)` with timing windows
  - Manages "phrases" (note sequences that activate the track)
  - Implements chunk-based streaming: loads/unloads `MeasureChunk` objects to manage memory
  - Audio volume states: `BLASTING_VOLUME`, `UNFOCUSED_VOLUME`, `MUTED_VOLUME`
- **SynRoadNote** (`entities/note.gd`) - Individual note hitboxes (3 lanes per track)
  - Simple visual state management: `blast()` shows ghost particle effect
  - Uses instrument-specific materials assigned by parent track

### Data Flow: MIDI → Resources → Gameplay
1. **Import**: MIDI files processed by `addons/midi_import/` plugin → creates `MidiData` resources
2. **Configuration**: Song folders (e.g., `song/drumnbass/`) contain:
   - `.mid` file with note data in MIDI note format
   - `.tres` file (`SongData` resource) with metadata, track mappings, audio file UIDs
   - Per-track `.wav` audio stems named like `00_T1_CATCH_D_DRUMS.wav`
   - Track names follow pattern: `T{N} CATCH:{Type}:{INSTRUMENT}` (e.g., `T3 CATCH:B:BASS`)
3. **Runtime**: `SongData.get_note_map_from_track()` extracts `Dictionary[float, int]` where:
   - Key = beat position (float, e.g., 16.5 for beat 16.5)
   - Value = lane index (0=left, 1=center, 2=right)
   - Difficulty (96/102/108/114) determines MIDI note offset for lane detection

### Timing & Spatial Mapping
- **Beat → Position**: Notes spawn at `z = -(beat_position * 4)` (4 units per beat)
- **Measure Calculation**: `measure_num = floor(beat / 4) + 1`
- **Hit Windows** (in `track.gd`):
  - `HIT_BEAT_WINDOW = 0.12` seconds (successful note hit)
  - `MISS_BEAT_WINDOW = 0.16` seconds (failed note, breaks streak)
- **Chunk Streaming**: Loads 3 chunks ahead, unloads 3 chunks behind current measure

### Signal-Driven Gameplay
Tracks emit signals to `SynRoadSong`:
- `started_phrase(score_value)` - Player began hitting a phrase
- `track_activated(score_value)` - Phrase completed, apply multiplier
- `streak_broken` - Missed note in active phrase
- `note_hit(timing)` - Individual note hit for stats tracking

## GDScript Conventions

### Resource Scripts
Use `@tool` directive for editor resources (`SongData`, `SongTrackData`):
```gdscript
@tool
extends Resource
class_name SongData
```

### Type Hints
Use typed collections introduced in Godot 4.x:
```gdscript
var note_map: Dictionary[float, int]
var phrase_notes: Array[SynRoadNote]
```

### UID System
Audio/scene references use Godot's UID system, not file paths:
```gdscript
newTrack.audio_file = ResourceUID.path_to_uid(track_data.audio_file)
asp.stream = load(audio_file) as AudioStream
```

### Scene Instantiation Pattern
```gdscript
const NOTE_SCENE:PackedScene = preload("res://entities/note.tscn")
var new_note = NOTE_SCENE.instantiate() as SynRoadNote
```

## Key Development Patterns

### Adding New Songs
1. Place MIDI + audio stems in `song/{songname}/` directory
2. Create `{songname}.tres` as `SongData` resource in Godot editor
3. Configure track mappings using MIDI track names (must match exactly)
4. Set `lead_in_measures` (countdown), `playable_measures`, `checkpoints` array
5. Assign click track and intro audio file UIDs

### Difficulty Configuration
Difficulties map to MIDI note numbers for lane detection:
- Beginner: 96 (C6), Intermediate: 102, Advanced: 108, Expert: 114
- Left lane = base note, Center = +2, Right = +4
- Notes must be encoded in MIDI file at these pitch values

### Modifying Timing Windows
Constants in `track.gd` control feel:
- `HIT_BEAT_WINDOW` - Tighten for harder difficulty
- `MISS_BEAT_WINDOW` - Determines auto-miss threshold
- `NOTE_VISIBILITY_RANGE_BEATS` - How far ahead notes render (64 beats default)

### Debugging Timing Issues
Check `song.gd` performance tracking variables:
- `_max_hit_offset`, `_avg_hit_offset` - Player accuracy stats
- `max_drift`, `total_drift` - Audio sync drift detection
- `frame_drops` - Performance issues causing timing problems

## Visual System

### Instance Shader Parameters
Measures and notes use instance shader parameters for per-object customization without material duplication:
- **Track geometry** (`measure.tscn`): Uses `trackshader.res` with parameters:
  - `measure_tint` - Set to instrument color on chunk load
  - `active` - Boolean highlighting the currently active track
  - `phrase` - Boolean highlighting upcoming phrase sequences
- **Note materials**: Use `noteshader.tres` with `NoteColor` instance parameter
  - Each instrument has a pre-configured material (e.g., `note_Bass_mat.tres`)
  - Set via `new_note.capsule_material = instrument_note_material`

### Shader Parameter Usage Pattern
```gdscript
// Set during chunk load
new_measure.get_node("track_geometry").set_instance_shader_parameter("measure_tint", INSTRUMENTS[track.instrument][1])

// Update during gameplay
measure.get_node("track_geometry").set_instance_shader_parameter("active", true)
```

## Running the Game
- **Direct song testing**: Open `menu/SongManager.tscn`, set exports (song file, difficulty, modifiers), use "Run Current Scene" (F6)
- **No formal build/test flow**: Development workflow uses scene preview with parameter tweaking
- Input actions defined in `project.godot`:
  - `note_left` (Z/gamepad), `note_center` (X), `note_right` (C)
  - `track_prev`, `track_next` for manual track switching (autoblast disabled)

## Test Songs for Specific Scenarios
Use these songs when testing specific gameplay mechanics or edge cases:
- **Spaztik**: Highest note density per measure (2x that of Out the Box) - stress test streaming, performance, hit detection at high note rates
- **The Winner**: Long noteless droughts on Guitar track - test chunk unloading, track switching during idle periods, phrase timeout behavior
- **Baseline [Beginner]**: "Squeezing" opportunities (manual play acceptable, autoblast should never squeeze) - validate autoblast timing logic doesn't activate phrases prematurely
- **The Rock Show**: Fastest BPM - test timing accuracy at tempo extremes, audio sync drift, visual spacing at high speeds

## Common Gotchas
- **MIDI track names must match exactly** between `.mid` file and `SongTrackData.midi_track_name`
- **BPM detection** can fail; use `SongData.bpm_fix = true` and set `fixed_bpm` manually
- **Chunk streaming** requires proper bounds checking (see `_update_note_streaming()`)
- **Freed notes in phrases** must be removed from `phrase_notes` array to prevent crashes
- **@tool scripts** execute in editor - guard runtime-only code with `Engine.is_editor_hint()`
