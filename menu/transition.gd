extends CanvasLayer

enum MenuTracks {
	SONG_SELECT,
	STATS,
	CHALLENGE,
	COUNT
}

const PLAYING_VOLUME_DB: float = 0.0
const MUTED_VOLUME_DB: float = -60.0

var _menu_music: AudioStreamPlayer
var _menu_music_stream: AudioStreamSynchronized
var _current_stream_idx: int = 0
var _vol_tween: Tween

signal animation_completed
signal audio_transition_completed

func _ready() -> void:
	_menu_music = $MenuMusic
	_menu_music_stream = _menu_music.stream as AudioStreamSynchronized
	
#region Visual transition functions
func start_transition_in():
	if !visible:
		show()
	$AnimationPlayer.play("build_in")

func start_transition_out():
	if visible:
		$AnimationPlayer.play("build_out")

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	animation_completed.emit()
	if anim_name == "build_out":
		hide()
#endregion

#region Audio functions

func play_menu_track(track: int, fade_time: float = 0.0):
	if track < 0 or track >= _menu_music_stream.stream_count:
		print("Invalid menu track: %d" % track)
		return
	if track == _current_stream_idx and _menu_music.playing:
		return
	if _menu_music.playing:
		if fade_time <= 0.0:
			for i in _menu_music_stream.stream_count:
				var vol = PLAYING_VOLUME_DB if i == track else MUTED_VOLUME_DB
				_menu_music_stream.set_sync_stream_volume(i, vol)
			_on_audio_transition_completed()
		else:
			if _vol_tween:
				_vol_tween.kill()
			_vol_tween = create_tween()
			for i in _menu_music_stream.stream_count:
				var vol = PLAYING_VOLUME_DB if i == track else MUTED_VOLUME_DB
				_vol_tween.tween_method(
					func(x): _menu_music_stream.set_sync_stream_volume(i, x),
					_menu_music_stream.get_sync_stream_volume(i),
					vol,
					fade_time
				).parallel()
		_vol_tween.tween_callback(_on_audio_transition_completed)
		_current_stream_idx = track
	else:
		for i in _menu_music_stream.stream_count:
			var vol = PLAYING_VOLUME_DB if i == track else MUTED_VOLUME_DB
			_menu_music_stream.set_sync_stream_volume(i, vol)
		_menu_music.volume_db = PLAYING_VOLUME_DB if fade_time <= 0 else MUTED_VOLUME_DB
		_menu_music.play()
		if fade_time > 0:
			if _vol_tween:
				_vol_tween.kill()
			_vol_tween = create_tween()
			_vol_tween.tween_property(_menu_music, "volume_db", PLAYING_VOLUME_DB, fade_time)
			_vol_tween.tween_callback(_on_audio_transition_completed)
		else:
			_on_audio_transition_completed()
		_current_stream_idx = track

func stop_menu_music(fade_time: float = 0.0):
	if _menu_music.playing:
		if fade_time <= 0.0:
			_menu_music.stop()
			_on_audio_transition_completed()
		else:
			if _vol_tween:
				_vol_tween.kill()
			_vol_tween = create_tween()
			_vol_tween.tween_property(_menu_music, "volume_db", MUTED_VOLUME_DB, fade_time)
			_vol_tween.tween_callback(_menu_music.stop)
			_vol_tween.tween_callback(_on_audio_transition_completed)

func set_menu_music_volume(volume_db: float, fade_time: float = 0.0):
	if fade_time <= 0.0:
		_menu_music.volume_db = volume_db
		_on_audio_transition_completed()
	else:
		if _vol_tween:
			_vol_tween.kill()
		_vol_tween = create_tween()
		_vol_tween.tween_property(_menu_music, "volume_db", volume_db, fade_time)
		_vol_tween.tween_callback(_on_audio_transition_completed)

func _on_audio_transition_completed() -> void:
	audio_transition_completed.emit()

#endregion
