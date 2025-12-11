extends Node

const CAMPAIGN_DATA_PATH = "user://campaign_data.json"
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
