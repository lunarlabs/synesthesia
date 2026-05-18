# Synesthesia Gameplay Context

## Gameplay Overview
Synesthesia is a multi-track rhythm game where the player acts as a dynamic "mixer" or "conductor" for a song. Unlike traditional rhythm games where the player follows a single chart, Synesthesia presents up to 6 parallel instrument tracks (e.g., Drums, Bass, Guitar, Synth, Vocals, FX).

### Core Loop
1.  **Navigation**: The player controls a **Playhead** that can switch between tracks using "Next" and "Prev" inputs. Only one track is **Active** at a time.
2.  **Blasting**: When focused on a track, the player hits notes (Left, Center, Right lanes) in sync with the music. This is called **Blasting**.
3.  **Phrases & Activation**: Notes are grouped into **Phrases**. Successfully completing all notes in a phrase **Activates** the track, which plays its audio stem at full volume automatically until the next **Reset Measure**.
4.  **Audio Mixing**:
    *   **Active Track** (player is focused here): Audio at `BLASTING_VOLUME` (-3 dB) while blasting, `UNFOCUSED_VOLUME` (-6 dB) when activated.
    *   **Activated (Background) Track**: Plays at `UNFOCUSED_VOLUME` (-6 dB), maintained by the game.
    *   **Inactive/Missed Track**: Muted (`MUTED_VOLUME`, -80 dB), removing that instrument from the mix.
5.  **Reset**: An activated track stays active until its **Reset Measure**. At that point it deactivates and the player must re-blast a new phrase to keep it going. The Reset Measure is determined per-phrase by `fast_track_reset` (default: 12 measures after phrase start).
6.  **Energy**: An 8-point health bar. Breaking streaks or leaving tracks inactive (when applicable) drains Energy. If Energy hits zero, the song fails. Some modifiers alter or disable this system.

---

## Key Definitions

### Game Entities
*   **SynRoadSong** (`entities/song.gd`): The main controller for a gameplay session. Manages the conductor, score, energy, streak, and all game state transitions.
*   **SynRoadTrack** (`entities/track.gd`): Represents a single instrument lane. Handles note spawning, visual rails, phrase progression, audio stem volume, and activation state.
*   **SynRoadNote** (`entities/note.gd`): The interactive hit objects. Notes are lane-specific (Left=0, Center=1, Right=2).
*   **SynRoadSongManager** (`menu/song_manager.gd`): The scene that owns and bootstraps a gameplay session. Loads song data on a worker thread, applies modifier settings from `SessionManager.modifiers`, instantiates `SynRoadSong`, and handles the result/fail flow.
*   **Playhead**: The 3D node representing player focus. Its Z position advances with the music; its X position shifts when switching tracks.
*   **Conductor** (`entities/conductor.gd`): Tracks playback time, current beat, and current measure. Emits `new_measure` signal. The authoritative timing source.

### Mechanisms
*   **Blasting**: Hitting a note within the hit window. Emits `note_hit` from the track.
*   **Misblast**: Hitting a note outside the window, or pressing a lane button when no note is available. Breaks the phrase in progress.
*   **Phrase**: A contiguous sequence of notes defined by the MIDI chart. The phrase is "started" when the first note is hit (`started_phrase` signal), and "completed" when all notes are blasted (`track_activated` signal). Phrases are indexed per-track (`current_phrase_index`).
*   **Phrase Marker**: A 3D visual indicator floating above the track at the next upcoming phrase start. The game highlights the *earliest upcoming* marker across all unactivated tracks to guide the player.
*   **Activation**: The state entered when a phrase is completed. The track plays its stem automatically until the Reset Measure. Visually, the track geometry is hidden for activated measures.
*   **Reset Measure**: The measure at which the current activation expires. Controlled by `fast_track_reset` modifier (12, 10, or 8 measures from phrase start). After this measure the player must blast again.
*   **Streak**: A counter incremented each time any phrase is *started* (on first note hit). Breaks on a missed phrase or misblast. Controls the score multiplier (capped at 4x). Streak breaks are deduplicated per measure.
*   **Autoblast**: A mode where the game automatically blasts all notes perfectly. Used for testing and previewing. Recorded results are flagged `AUTOBLASTED`.
*   **Suppressed Measure**: A measure where missed notes do not trigger penalties (used around checkpoints and the lead-in).
*   **Lead-In**: A countdown period at the start of a song (measured in measures) before playable notes begin.

### Scoring & Results
*   **Score**: Each phrase activation adds `phrase_note_count × streak_multiplier` points.
*   **Accuracy**: Calculated as `phrases_completed / (phrases_completed + phrases_missed) × 100`. This is **phrase-capture rate**, not individual note accuracy.
*   **Rank**: Derived from accuracy on a clean clear. Thresholds: AAA ≥97%, AA ≥93%, A ≥90%, B ≥80%, C ≥70%, D ≥60%, E ≥50%, F <50%.
*   **Clear States** (in `SessionManager.SongResult.ClearState`):
    *   `NOT_PLAYED` — no result recorded.
    *   `AUTOBLASTED` — completed in autoblast mode (not a valid record).
    *   `FAILED` — energy reached zero before song end.
    *   `LOOSE_CLEAR` — completed with Loose timing modifier.
    *   `CLEAR` — completed with Normal timing.
    *   `STRICT_CLEAR` — completed with Strict timing modifier.
    *   `PERFECT_RUN` — completed with zero streak breaks (any timing).

### Modifiers
Modifiers are set in `SessionManager.modifiers` before a song starts and read by `SynRoadSongManager._ready()`.

#### Energy Modifier (`energy_modifier`)
Controls the health/energy system behavior.
| Value | Name | Behavior |
|---|---|---|
| 0 | Normal | Start at 8. Gain 1 per phrase, lose 1 per streak break. Gain 2 at checkpoint. |
| 1 | Constant Drain | Start at 5. Gain 3 per phrase. Lose 1 per unactivated track measure. |
| 2 | No Recover | Lose 1 per streak break. No gains. |
| 3 | Sudden Death | Any streak break instantly fails the song. |
| 4 | No Fail | Energy system disabled; the song cannot be failed. |

#### Checkpoint Modifier (`checkpoint_modifier`)
Controls behavior at **Checkpoint** gates (defined in the song data).
| Value | Name | Behavior |
|---|---|---|
| 0 | Normal | Crossing a checkpoint restores 2 energy. Two measures around it are suppressed. |
| 1 | Disabled | Checkpoints exist visually but have no gameplay effect. |
| 2 | Barrier 2x | Requires streak ≥ 2 to pass. Failure = energy penalty. See Barrier Mode. |
| 3 | Barrier 3x | Requires streak ≥ 3. |
| 4 | Barrier 4x | Requires streak ≥ 4. |

**Barrier Mode detail**: A 10-measure warning zone precedes each checkpoint gate. Track activations within the zone have their `reset_measure` capped to the checkpoint measure + 2. On a successful crossing, the capped activations are **restored** to their full original length (`restore_barrier_activation`). On failure, the player takes an energy penalty scaled to current energy (always leaves at least 2 energy, unless already ≤ 2).

#### Timing Modifier (`timing_modifier`)
Controls the hit window for blasting notes.
| Value | Name | Hit Window |
|---|---|---|
| 0 | Normal | ±80 ms |
| 1 | Loose | ±100 ms |
| 2 | Strict | ±60 ms |

A miss window of hit_window + 10 ms is used for streak-break detection.

#### Track Reset (`fast_track_reset`)
Controls how many measures after phrase start the activation lasts.
| Value | Name | Duration |
|---|---|---|
| 12 | Normal | 12 measures |
| 10 | Fast Reset 1 | 10 measures |
| 8 | Fast Reset 2 | 8 measures |

### Data & Resources
*   **SongData** (`.tres` Godot Resource): The main resource the game loads. Contains BPM, lead-in measures, checkpoint measures, track definitions (`SongTrackData[]`), and a reference to the MIDI data.
*   **SongTrackData**: Metadata for one instrument track — instrument type, MIDI track name, audio stem path.
*   **MoggSong** (`.moggsong`): Source authoring format defining song structure, sections, and checkpoints. Converted to `SongData` via the `moggsong_to_synroad` addon.
*   **MidiData** (`.mid`): Standard MIDI files defining note charts per instrument and per difficulty.
*   **GameplayTrackData** (`SynRoadTrack.GameplayTrackData`): The preprocessed, runtime-ready note data for a single track. Built by `SynRoadTrackPreprocessor` on a worker thread. Contains note times, lane assignments, phrase indices, phrase boundaries, and barrier cache.
*   **Stems**: Individual audio files (`.ogg` or `.wav`) per instrument track, synchronized via `AudioStreamSynchronized`.

### Difficulties
Songs have up to 4 difficulty tiers, selected in song select. Each maps to a MIDI velocity range:
| Value | Name |
|---|---|
| 96 | Beginner |
| 102 | Intermediate |
| 108 | Advanced |
| 114 | Expert |

### Instruments
Tracks are typed to one of 6 instruments (order matters — it's an index, not a string):
| Index | Name | Color |
|---|---|---|
| 0 | Drums | Purple |
| 1 | Bass | Blue |
| 2 | Guitar | Red |
| 3 | Synth | Yellow |
| 4 | Vocals | Green |
| 5 | FX | Cyan |

---

## File Map

### Gameplay Logic
*   `entities/song.gd` — `SynRoadSong`. Master game session controller: input, energy, streak, score, track switching, checkpoints, barrier crossings.
*   `entities/track.gd` — `SynRoadTrack`. Per-instrument lane: note processing, phrase logic, activation, audio volume, visual state, marker positioning.
*   `entities/note.gd` — `SynRoadNote`. Individual hit object.
*   `entities/conductor.gd` — Beat/measure clock, synced to `AudioStreamPlayer`. Source of truth for timing.
*   `entities/track_preprocessor.gd` — `SynRoadTrackPreprocessor`. Runs on `WorkerThreadPool`. Builds `GameplayTrackData` from raw note maps (phrase detection, lane assignment, barrier capping).
*   `entities/checkpoint.gd` — The 3D gate visual and logic for checkpoint/barrier markers.
*   `entities/chunk_manager.gd` — Manages streaming of 3D geometry in/out of the scene in 8-measure chunks.

### Session & Data Management
*   `entities/managers/session_manager.gd` — `SessionManager` (autoload). Holds `modifiers` dict for the current session, manages SQLite databases (`library.db`, `player.db`), records and retrieves song results. Contains `SongResult` class with `ClearState` and `ClearRank` enums.
*   `menu/song_manager.gd` — `SynRoadSongManager`. Owns a live gameplay session. Reads modifiers from `SessionManager`, runs `_prepare_song_data` on a thread, instantiates `SynRoadSong`, handles fail/finish callbacks and result display.
*   `menu/song_catalog.gd` — `SongCatalog`. Scans for and indexes available songs. Provides catalog entries to song select.

### Menu & UI
*   `menu/song_select.gd` — Song select carousel and UI. Sets `SessionManager.modifiers` before launching a song.
*   `menu/modifier_container.gd` — The in-menu modifier picker UI. Writes selected modifier values.
*   `menu/song_result.gd` — Post-song result screen (score, rank, clear state, personal best).
*   `menu/transition.gd` — `Transition` (autoload). Scene transitions and menu music management.

### Data Conversion (Authoring)
*   `addons/moggsong_to_synroad/moggsong_to_synroad.gd` — Editor tool. Converts `.moggsong` + MIDI into `SongData` `.tres` resources.
