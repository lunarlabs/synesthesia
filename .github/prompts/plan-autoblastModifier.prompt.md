# Plan: Autoblast Modifier Implementation

This plan adds an autoplay/demo mode using the existing `autoblast` export variable in `song.gd`. The system will automatically switch to tracks with upcoming phrases (max 3 measures lookahead) and play notes with strict timing precision.

## Steps

1. **Extract track switching logic in `song.gd`**: The manual track switching code (lines 155-167) should be refactored into a reusable `_switch_to_track(track_index:int)` method. This existing code already handles deactivation via `set_active(false)`, activation via `set_active(true)`, instrument label updates via `_set_instrument_label()`, and tweening of `currentTrack` and `camera` positions. The method should call `_switch_active_track(track_index)` which contains the implementation.

2. **Add intelligent track selection in `song.gd`**: Create `_find_best_track_for_autoblast() -> int` that uses the existing helper methods `_get_phrase_distances()` and `_get_next_phrase_values()`. It should find tracks with phrases within 3 measures of `currentMeasure()` (phrase_distance between 0-3), exclude the current track if `(tracks[activeTrack] as SynRoadTrack).blasting_phrase == true`, and return best match using tie-breaking: prefer current track if eligible, otherwise choose track with highest phrase value from `_get_next_phrase_values()`, defaulting to `activeTrack` if no tracks qualify.

3. **Implement autoblast track switching in `song.gd._process()`**: In the section where `leadInMeasures < 1` (after line 147), add autoblast logic before the manual input handling. When `autoblast` is enabled, get `_active_track_node` and check if current track is not blasting (`!_active_track_node.blasting_phrase`), then call `_find_best_track_for_autoblast()` and if result differs from `activeTrack`, call `_switch_active_track(result)`.

4. **Add automatic note playing in `track.gd._process()`**: Check `songNode.autoblast`, iterate through `lane_note_beats` arrays, and call `try_blast(lane_index)` when `current_beat` is within 0-0.05 beats ahead of target note for perfect strict timing hits.

5. **Manual note inputs are already properly guarded**: Lines 154-167 already wrap input handling with `if !autoblast:`, so manual note blasting is prevented when autoblast is active. The note blasting itself (lines 169-175) is also inside this guard. No changes needed.

6. **Autoblast indicator label already exists**: The code already has `@onready var lblAutoBlast = $AutoblastLabel` (line 56) and shows/hides it in `_ready()` (lines 106-109) based on the `autoblast` variable. No changes needed.

## Further Considerations

1. **Track selection tie-breaking strategy**: When multiple tracks have phrases starting at the same distance, using `_get_next_phrase_values()` to prefer higher-scoring phrases makes sense for maximizing score. However, should we also consider `phraseNotes.size()` as a secondary tie-breaker, or is phrase value sufficient?

2. **Autoblast timing window of 0.05 beats appropriate?** At 120 BPM this is ~25ms early. For strict perfect timing, consider tightening to 0.02-0.03 beats or matching the existing `HIT_BEAT_WINDOW` constant if it exists in `track.gd`.

3. **Track switching during active phrase**: The plan excludes the current track if `blasting_phrase == true`, but should we also check `just_activated` flag? The `_on_inactive_phrase_missed()` logic (lines 203-205) suggests `just_activated` is important for phrase state.

4. **Edge case: All tracks beyond 3 measure lookahead**: The plan recommends returning `activeTrack` to stay put, but should autoblast switch to the track with the nearest phrase (even if >3 measures away) to position optimally, or truly stay put until something comes into range?
