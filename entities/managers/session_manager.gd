extends Node

const LIBRARY_DB_VERSION = 1
const PLAYER_DB_VERSION = 1
const LIBRARY_DB_PATH = "user://library.db"
const PLAYER_DB_PATH = "user://player.db"
const LIBRARY_DDL_PATH = "res://data/library.sql"
const PLAYER_DDL_PATH = "res://data/player.sql"

var _library_db: SQLite = null
var _player_db: SQLite = null
var player_attached := false

var previous_select_options: Dictionary = {}

#region Database Functions
var library_db: SQLite:
	get:
		if not _library_db:
			_prepare_library_db()
		return _library_db

var player_db: SQLite:
	get:
		if not _player_db:
			_prepare_player_db()
		return _player_db

func close_library_db():
	if _library_db:
		_library_db.close_db()
		_library_db = null

func close_player_db():
	if _player_db:
		_player_db.close_db()
		_player_db = null

func _exit_tree():
	close_library_db()
	close_player_db()

func _prepare_library_db():
	if not _library_db:
		_library_db = SQLite.new()
		_library_db.path = LIBRARY_DB_PATH
		_library_db.foreign_keys = true
		if _library_db.open_db() == false:
			printerr("Problem opening library database!")
			return
		_library_db.query("PRAGMA user_version;")
		if _library_db.query_result[0]["user_version"] == 0:
			print("Initializing library database...")
			var ddl = FileAccess.get_file_as_string(LIBRARY_DDL_PATH)
			if _library_db.query(ddl):
				print("Library database initialized OK.")
			else:
				printerr("Problem initializing library database!")
		elif _library_db.query_result[0]["user_version"] == LIBRARY_DB_VERSION:
			print("Library database is up to date.")
		else:
			printerr("Library database version mismatch!")
			return
		
func _prepare_player_db():
	if not _player_db:
		_player_db = SQLite.new()
		_player_db.path = PLAYER_DB_PATH
		_player_db.foreign_keys = true
		if _player_db.open_db() == false:
			printerr("Problem opening player database!")
			return
		_player_db.query("PRAGMA user_version;")
		var current_version = int(_player_db.query_result[0]["user_version"])
		print("Player database version: %d" % current_version)
		
		if current_version == 0:
			print("Initializing player database...")
			var ddl = FileAccess.get_file_as_string(PLAYER_DDL_PATH)
			if _player_db.query(ddl):
				print("Player database initialized OK.")
			else:
				printerr("Problem initializing player database!")
		elif current_version < PLAYER_DB_VERSION:
			print("Updating player database from version %d to %d..." % [current_version, PLAYER_DB_VERSION])
			if _update_player_db(current_version):
				print("Player database updated OK.")
			else:
				printerr("Problem updating player database!")
		elif current_version == PLAYER_DB_VERSION:
			print("Player database is up to date.")
		else:
			printerr("Player database version mismatch! (DB: %d, App: %d)" % [current_version, PLAYER_DB_VERSION])
			return

func _update_player_db(current_version: int) -> bool:
	# Iterate through versions to apply updates sequentially
	for v in range(current_version + 1, PLAYER_DB_VERSION + 1):
		print("Applying migration to version %d..." % v)
		match v:
			# Example:
			# 2:
			# 	if not _player_db.query("ALTER TABLE..."): return false
			_:
				printerr("No migration defined for version %d" % v)
				return false
				
	# Update the user_version pragma after successful migration
	return _player_db.query("PRAGMA user_version = %d;" % PLAYER_DB_VERSION)
#endregion

#region Player Data
class SongResult:
	enum ClearState {
		NOT_PLAYED,
		AUTOBLASTED,
		FAILED,
		LOOSE_CLEAR,
		CLEAR,
		STRICT_CLEAR,
		PERFECT_RUN,
	}

	enum ClearRank {
		INVALID,
		F,
		E,
		D,
		C,
		B,
		A,
		AA,
		AAA,
	}

	const ACCURACY_THRESHOLDS = {
		97.0: ClearRank.AAA,
		93.0: ClearRank.AA,
		90.0: ClearRank.A,
		80.0: ClearRank.B,
		70.0: ClearRank.C,
		60.0: ClearRank.D,
		50.0: ClearRank.E,
		0.00: ClearRank.F,
	}
	var song: String
	var title: String
	var artist: String
	var difficulty: int = 102
	var energy_modifier: int
	var checkpoint_modifier: int
	var hide_streak_hints: bool
	var timing_modifier: int
	var fast_track_reset: int
	var score: int = 0
	var max_streak: int = 0
	var accuracy: float = 0.0
	var streak_breaks: int = 9999
	var clear_state: ClearState = ClearState.NOT_PLAYED
	var rank: ClearRank = ClearRank.INVALID
	var percent_completed: float = 0.0

	func calculate_rank():
		for threshold in ACCURACY_THRESHOLDS.keys():
			if accuracy >= threshold:
				rank = ACCURACY_THRESHOLDS[threshold]
				break
	
	func get_rank_string() -> String:
		match rank:
			ClearRank.AAA:
				return tr("RANK_AAA")
			ClearRank.AA:
				return tr("RANK_AA")
			ClearRank.A:
				return tr("RANK_A")
			ClearRank.B:
				return tr("RANK_B")
			ClearRank.C:
				return tr("RANK_C")
			ClearRank.D:
				return tr("RANK_D")
			ClearRank.E:
				return tr("RANK_E")
			ClearRank.F:
				return tr("RANK_F")
			_:
				return "--"
	
	func get_clear_string(short := false) -> String:
		match clear_state:
			ClearState.NOT_PLAYED:
				return tr("MENU_NOTPLAYED")
			ClearState.AUTOBLASTED:
				return tr("RANK_AUTOBLAST")
			ClearState.FAILED:
				return tr("MENU_FAILED")
			ClearState.LOOSE_CLEAR:
				return tr("MENU_LOOSE_CLEARED_SHORT") if short else tr("MENU_LOOSE_CLEARED")
			ClearState.CLEAR:
				return tr("MENU_CLEARED")
			ClearState.STRICT_CLEAR:
				return tr("MENU_TIGHT_CLEARED_SHORT") if short else tr("MENU_TIGHT_CLEARED")
			ClearState.PERFECT_RUN:
				return tr("MENU_PERFECTRUN_SHORT") if short else tr("MENU_PERFECTRUN")
			_:
				return "???"

	func to_dict() -> Dictionary:
		return {
			"song" = song,
			"title" = title,
			"artist" = artist,
			"difficulty" = difficulty,
			"energy_modifier" = energy_modifier,
			"checkpoint_modifier" = checkpoint_modifier,
			"hide_streak_hints" = hide_streak_hints,
			"timing_modifier" = timing_modifier,
			"fast_track_reset" = fast_track_reset,
			"score" = score,
			"max_streak" = max_streak,
			"accuracy" = accuracy,
			"streak_breaks" = streak_breaks,
			"clear_state" = clear_state,
			"rank" = rank,
			"percent_completed" = percent_completed,
		}

	static func from_dict(dict: Dictionary) -> SongResult:
		var result = SongResult.new()
		result.song = dict.get("song", "")
		result.title = dict.get("title", "Unknown Song")
		result.artist = dict.get("artist", "Unknown Artist")
		result.difficulty = int(dict.get("difficulty", 102))
		result.energy_modifier = int(dict.get("energy_modifier", 0))
		result.checkpoint_modifier = int(dict.get("checkpoint_modifier", 0))
		result.hide_streak_hints = dict.get("hide_streak_hints", false)
		result.fast_track_reset = int(dict.get("fast_track_reset", 12))
		result.score = int(dict.get("score", 0))
		result.max_streak = int(dict.get("max_streak", 0))
		result.accuracy = dict.get("accuracy", 0.0)
		result.streak_breaks = int(dict.get("streak_breaks", 9999))
		result.clear_state = int(dict.get("clear_state", ClearState.NOT_PLAYED))
		result.rank = int(dict.get("rank", ClearRank.INVALID))
		result.percent_completed = dict.get("percent_completed", 0.0)
		return result

func record_song_result(midi_hash: String, song_stats: SongResult):
	const TIMING_ORDER = [2, 1, 3]
	var insert_row := {
		"midi_hash" = midi_hash,
		"difficulty" = song_stats.difficulty,
		"score" = song_stats.score,
		"percent_complete" = song_stats.percent_completed,
		"capture_accuracy" = song_stats.accuracy if song_stats.accuracy else 0.0,
		"streak_breaks" = song_stats.streak_breaks,
		"energy_modifier" = song_stats.energy_modifier + 1, # the SQL records are 1-based
		"checkpoint_modifier" = song_stats.checkpoint_modifier + 1,
		"timing_modifier" = TIMING_ORDER[song_stats.timing_modifier],
		"track_reset" = song_stats.fast_track_reset,
		"max_streak" = song_stats.max_streak,
	}

	if song_stats.rank != SongResult.ClearRank.INVALID:
		insert_row["rank"] = song_stats.rank

	match song_stats.clear_state:
		SongResult.ClearState.PERFECT_RUN:
			insert_row["status"] = 4
		SongResult.ClearState.CLEAR, SongResult.ClearState.LOOSE_CLEAR, SongResult.ClearState.STRICT_CLEAR:
			insert_row["status"] = 3
		SongResult.ClearState.FAILED:
			insert_row["status"] = 2
		SongResult.ClearState.NOT_PLAYED, SongResult.ClearState.AUTOBLASTED, _:
			insert_row["status"] = 1

	var success = SessionManager.player_db.insert_row("player_records", insert_row)
	if not success:
		printerr(SessionManager.player_db.error_message)

@warning_ignore("unused_parameter")
func get_song_best_record(midi_hash: String, difficulty: int) -> SongResult:
	var result = SongResult.new()
	var success = SessionManager.player_db.query_with_bindings("SELECT * FROM v_bests WHERE midi_hash = ? AND difficulty = ?", [midi_hash, difficulty])
	if not success:
		printerr(SessionManager.player_db.error_message)
		return result
	if SessionManager.player_db.query_result.size() == 0:
		return result
	result.score = SessionManager.player_db.query_result[0]["best_score"]
	result.percent_completed = SessionManager.player_db.query_result[0]["furthest_complete"]
	if player_db.query_result[0]["max_rank"]:
		result.rank = SessionManager.player_db.query_result[0]["max_rank"]
	result.max_streak = SessionManager.player_db.query_result[0]["best_streak"]
	result.accuracy = SessionManager.player_db.query_result[0]["best_accuracy"]
	
	match SessionManager.player_db.query_result[0]["max_status"]:
		1:
			result.clear_state = SongResult.ClearState.NOT_PLAYED
		2:
			result.clear_state = SongResult.ClearState.FAILED
		3:
			match SessionManager.player_db.query_result[0]["max_timing"]:
				1:
					result.clear_state = SongResult.ClearState.LOOSE_CLEAR
				2:
					result.clear_state = SongResult.ClearState.CLEAR
				3:
					result.clear_state = SongResult.ClearState.STRICT_CLEAR
				_:
					result.clear_state = SongResult.ClearState.NOT_PLAYED
		4:
			result.clear_state = SongResult.ClearState.PERFECT_RUN
		_:
			result.clear_state = SongResult.ClearState.NOT_PLAYED
	return result
#endregion
