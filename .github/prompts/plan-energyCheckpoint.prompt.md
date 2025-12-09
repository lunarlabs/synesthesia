# Energy and Checkpoint System Plan

## Energy System

**Energy maximum:** 8 units

### Energy Modifiers

**Normal:** -1 any time a streak break happens, +1 on activation. If a streak break brings energy to zero, the song is failed.

**Drain:** -1 on the start of a new measure when *any* track is not activated or empty, +3 on activation. If the new measure on the active track is a phrase measure, allow the player to attempt the phrase.

**No Recover:** Like Normal but without the activation restoration. This mode should also set "No Checkpoint."

## Checkpoint System

### Checkpoint Modifiers

**Normal:** Passing a checkpoint grants +2 energy. The two measures after the checkpoint should be empty/activated so that players get a short break without having to blast notes.

**Barrier variants:** Barrier 2, Barrier 3, Barrier 4
- Start with 4/8 energy
- Track activation lengths are adjusted so that all tracks are reset eight measures before the barrier
- A warning should be visible ten measures before the barrier
- Inside this "danger zone," all activations stop at the barrier
- If the player crosses the barrier with a high enough multiplier (2, 3, or 4 respectively), they get the usual +2 energy and any tracks beyond the barrier will activate with the remainder of their track activation length
- Otherwise, -2 energy

## Implementation Notes

**Empty measure definition:** A measure that is activated or has no notes on it.

**Codebase integration points:**
- Energy tracking: Add `energy: int` variable in `song.gd`
- Drain detection: Check `track.is_active` and `track.get_notes_in_measure()` on each new measure
- Checkpoint rewards: Hook into existing `song_data.checkpoints` positions
- Barrier logic: Modify `activation_length_measures` dynamically when approaching checkpoints
- Track state: Use existing `track.is_active`, `reset_countdown`, and `track_activated` signal
