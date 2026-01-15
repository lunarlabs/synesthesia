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
		var data = json.data
		if typeof(data) == TYPE_DICTIONARY:
			# TODO: Player options and player records
			var sr = data.get("song_records", {})
			for song in sr.keys():
				song_records[song] = {}
				for diff in DIFFICULTY_VALUES.keys():
					if sr[song].has(str(diff)):
						song_records[song][diff] = {
							"accuracy": sr[song][str(diff)].get("accuracy", 0.0),
							"clear_state": sr[song][str(diff)].get("clear_state", "not_played"),
							"max_streak": int(sr[song][str(diff)].get("max_streak", 0)),
							"percent_completed": sr[song][str(diff)].get("percent_completed", 0.0),
							"rank": sr[song][str(diff)].get("rank", ""),
							"score": int(sr[song][str(diff)].get("score", 0)),
							"streak_breaks": int(sr[song][str(diff)].get("streak_breaks", 0)),
						}
					
	else:
		push_error("Failed to parse JSON data: %s" % json.get_error_message())
		return

func save_campaign_data() -> Error:
	var file = FileAccess.open(CAMPAIGN_DATA_PATH, FileAccess.WRITE)
	if not file:
		push_error("Failed to open file for writing: %s" % CAMPAIGN_DATA_PATH)
		return file.get_error()
	var result = {}
	result["song_records"] = song_records
	result["player_options"] = player_options
	result["player_records"] = player_records
	file.store_string(JSON.stringify(result))
	file.close()
	return OK

func record_song_result(song_id: String, difficulty: int, result: SongResult) -> void:
	if not song_records.has(song_id):
		song_records[song_id] = {}
	song_records[song_id][difficulty] = result

class SongResult:

	enum ClearState{
		NOT_PLAYED,
		AUTOBLASTED,
		FAILED,
		LOOSE_CLEAR,
		CLEAR,
		STRICT_CLEAR,
		PERFECT_RUN,
	}

	enum ClearRank{
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
		0.97: ClearRank.AAA,
		0.93: ClearRank.AA,
		0.90: ClearRank.A,
		0.80: ClearRank.B,
		0.70: ClearRank.C,
		0.60: ClearRank.D,
		0.50: ClearRank.E,
		0.00: ClearRank.F,
	}

	var energy_modifier: int
	var checkpoint_modifier: int
	var hide_streak_hints: bool
	var timing_modifier: int
	var fast_track_reset: int
	var score: int
	var max_streak: int
	var accuracy: float
	var streak_breaks: int
	var clear_state: ClearState
	var rank: ClearRank = ClearRank.INVALID
	var percent_completed: float

	func calculate_rank():
		for threshold in ACCURACY_THRESHOLDS.keys():
			if accuracy >= threshold:
				clear_state = ACCURACY_THRESHOLDS[threshold]
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
	
	func get_clear_string(short:= false) -> String:
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
				return tr("MENU_LOOSE_TIGHT_SHORT") if short else tr("MENU_TIGHT_CLEARED")
			ClearState.PERFECT_RUN:
				return tr("MENU_PERFECTRUN_SHORT") if short else tr("MENU_PERFECTRUN")
			_:
				return "???"
