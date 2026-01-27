# Synesthesia Gameplay Context

## Gameplay Overview
Synesthesia is a multi-track rhythm game where the player acts as a dynamic "mixer" or "conductor" for a song. Unlike traditional rhythm games where the player follows a single chart, Synesthesia presents up to 6 parallel instrument tracks (e.g., Drums, Bass, Guitar, Synth, Vocals, FX).

### Core Loop
1.  **Navigation**: The player controls a **Playhead** that can switch between these tracks using "Next" and "Prev" inputs.
2.  **Blasting**: When focused on a specific track, the player must hit notes (Left, Center, Right) in sync with the music. This action is called **Blasting**.
3.  **Phrases & Activation**: Notes are grouped into **Phrases**. Successfully completing a phrase **Activates** the track.
4.  **Audio Mixing**:
    *   **Active Track**: Plays at full volume.
    *   **Activated (Background) Track**: Plays at full volume (maintained by the game).
    *   **Inactive/Missed Track**: Muted or quiet (Unfocused volume), removing that instrument from the mix.
5.  **Reset**: An activated track remains active for a set duration until it hits a **Reset Measure**. At this point, it deactivates, and the player must switch back to it and blast a new phrase to keep the music going.
6.  **Energy**: A health bar system. Missing notes, breaking streaks, or leaving tracks inactive for too long drains Energy. If Energy hits zero, the song fails.

## Key Definitions

### Game Entities
*   **SynRoad**: The internal class prefix and project name for the gameplay logic.
*   **Song (SynRoadSong)**: The main controller (`entities/song.gd`) for a gameplay session. Manages the conductor, score, energy, and game state.
*   **Track (SynRoadTrack)**: Represents a single instrument lane (`entities/track.gd`). Handles not spawning, visual rails, and audio stems.
*   **Note (SynRoadNote)**: The interactive hit objects (`entities/note.gd`). Notes are lane-specific (Left, Center, Right).
*   **Playhead**: The visual representation of the player's focus. It moves across the x-axis to select tracks.

### Mechanisms
*   **Blasting**: The act of pressing the correct note input timing with the music.
*   **Phrase**: A specific sequence of notes marked by a "Phrase Marker". Hitting these notes builds the phrase meter.
*   **Activation**: The state of a track after a phrase is successfully completed. An activated track visually lights up and plays its audio automatically until the reset point.
*   **Reset Measure**: The specific measure in the song where a track's current activation ends. The player should return to the track before this point to chain activations.
*   **Streak**: A counter for consecutive successful phrases (not just individual notes). Streak builds up a score multiplier (1x to 4x).
*   **Autoblast**: An assist/cheat mode where the game automatically plays the tracks, often used for testing.

### Data & Resources
*   **MoggSong**: The source file format (`.moggsong`) used to define song metadata, sections, and structure.
*   **MidiData**: Standard MIDI files (`.mid`) used to define the note charts for each instrument.
*   **SongData**: The Godot Resource (`.tres`) generated from MoggSong and MIDI data. This is what the game actually loads.
*   **Stems**: Individual audio files (`.wav` or `.ogg`) for each instrument track.

## File Map
*   **Gameplay Logic**: `entities/song.gd`, `entities/track.gd`, `entities/note.gd`
*   **Input Handling**: `entities/song.gd` (see `_unhandled_input`)
*   **Data Conversion**: `addons/moggsong_to_synroad/moggsong_to_synroad.gd`
*   **Menu/UI**: `menu/song_select.gd`, `menu/song_result.gd`
