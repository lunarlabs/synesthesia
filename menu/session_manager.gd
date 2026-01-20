extends Node

const CAMPAIGN_DATA_PATH = "user://campaign_data.json"
const CONFIGURATION_PATH = "user://syn_road.cfg"
const SONG_RECORD_PATH = "user://song_records.json"
const DIFFICULTY_VALUES = {
	96: "Beginner",
	102: "Intermediate",
	108: "Advanced",
	114: "Expert"
}

const ENERGY_MODIFIER_NAMES = [
	"Normal",
	"Drain",
	"No Recover",
	"S.Death",
    "No Fail"
]
const CHECKPOINT_MODIFIER_NAMES = [
	"Normal",
	"No Checkpoint",
	"Barrier 2x",
	"Barrier 3x",
	"Barrier 4x"
]
const TIMING_MODIFIER_NAMES = [
	"Normal",
	"Loose",
    "Strict"
]

const FAST_RESET_NAMES = {
	12: "Normal",
	10: "Fast Reset 1",
	8: "Fast Reset 2"
}

const SCORE_RANKS = [
	"AAA",
	"AA",
	"A",
	"B",
	"C",
	"D",
	"E",
	"F",
]

var song_records: Dictionary = {}
var session_data: Dictionary = {}
var player_options: Dictionary = {}
var player_records: Dictionary = {}
var previous_select_options: Dictionary = {}

func _ready():
	load_campaign_data()

func load_campaign_data():
	if not FileAccess.file_exists(CAMPAIGN_DATA_PATH):
		return
	var file = FileAccess.open(CAMPAIGN_DATA_PATH, FileAccess.READ)
	if not file:
		push_error("Failed to open file for reading: %s" % CAMPAIGN_DATA_PATH)
		return
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	if error == OK:
		pass
					
	else:
		push_error("Failed to parse JSON data: %s" % json.get_error_message())
		return

func save_campaign_data() -> Error:
	var file = FileAccess.open(CAMPAIGN_DATA_PATH, FileAccess.WRITE)
	if not file:
		push_error("Failed to open file for writing: %s" % CAMPAIGN_DATA_PATH)
		return file.get_error()
	var result = {}
	result["player_options"] = player_options
	result["player_records"] = player_records
	file.store_string(JSON.stringify(result))
	file.close()
	return OK

func record_song_result(song_id: String, difficulty: int, result: SongResult) -> void:
	if not song_records.has(song_id):
		song_records[song_id] = {}
	var sr = song_records[song_id]
	if not sr.has(str(difficulty)):
		sr[str(difficulty)] = result
	else:
		var sd = sr[str(difficulty)] as SongResult
		sd.score = max(result.score, sd.score)
		sd.max_streak = max(result.max_streak, sd.max_streak)
		sd.accuracy = max(result.accuracy, sd.accuracy)
		sd.streak_breaks = min(result.streak_breaks, sd.streak_breaks)
		sd.percent_completed = max(result.percent_completed, sd.percent_completed)
		sd.clear_state = max(result.clear_state, sd.clear_state)
		sd.rank = min(result.rank, sd.rank) if result.rank != SongResult.ClearRank.INVALID else sd.rank

func get_song_record(song_id: String, difficulty: int) -> SongResult:
	if song_records.has(song_id):
		return song_records[song_id].get(str(difficulty), SongResult.new())
	else:
		return SongResult.new()

func save_song_records() -> Error:
	var file = FileAccess.open(SONG_RECORD_PATH, FileAccess.WRITE)
	if not file:
		push_error("Failed to open file for writing: %s" % SONG_RECORD_PATH)
		return file.get_error()
	var out_json := {}
	for song_id in song_records.keys():
		out_json[song_id] = {}
		for diff in song_records[song_id].keys():
			out_json[song_id][diff] = song_records[song_id][diff].to_dict()
	file.store_string(JSON.stringify(out_json))
	file.close()
	return OK

func load_song_records() -> Error:
	if not FileAccess.file_exists(SONG_RECORD_PATH):
		return OK
	var file = FileAccess.open(SONG_RECORD_PATH, FileAccess.READ)
	if not file:
		push_error("Failed to open file for reading: %s" % SONG_RECORD_PATH)
		return file.get_error()
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	if error == OK:
		pass
	else:
		push_error("Failed to parse JSON data: %s" % json.get_error_message())
		return error
	var in_json = json.get_data()
	for song_id in in_json.keys():
		song_records[song_id] = {}
		for diff in in_json[song_id].keys():
			song_records[song_id][diff] = SongResult.from_dict(in_json[song_id][diff])
	file.close()
	return OK

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
		AAA,
		AA,
		A,
		B,
		C,
		D,
		E,
		F,
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
