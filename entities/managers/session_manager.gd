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

var library_db: SQLite:
	get: return _library_db

var player_db: SQLite:
	get: return _player_db

func _ready():
	_prepare_library_db()
	_prepare_player_db()

func _exit_tree():
	_library_db.close_db()
	_player_db.close_db()
	_library_db = null
	_player_db = null

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
		if _player_db.query_result[0]["user_version"] == 0:
			print("Initializing player database...")
			var ddl = FileAccess.get_file_as_string(PLAYER_DDL_PATH)
			if _player_db.query(ddl):
				print("Player database initialized OK.")
			else:
				printerr("Problem initializing player database!")
		elif _player_db.query_result[0]["user_version"] == PLAYER_DB_VERSION:
			print("Player database is up to date.")
		else:
			printerr("Player database version mismatch!")
			return

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
		INVALID = -1,
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
		result.fast_track_reset = int(dict.get("fast_track_reset", 0))
		result.score = int(dict.get("score", 0))
		result.max_streak = int(dict.get("max_streak", 0))
		result.accuracy = dict.get("accuracy", 0.0)
		result.streak_breaks = int(dict.get("streak_breaks", 9999))
		result.clear_state = int(dict.get("clear_state", ClearState.NOT_PLAYED))
		result.rank = int(dict.get("rank", ClearRank.INVALID))
		result.percent_completed = dict.get("percent_completed", 0.0)
		return result