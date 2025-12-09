extends Node

const CAMPAIGN_DATA_PATH = "user://campaign_data.json"
const DIFFICULTY_VALUES = {
	96: "Beginner",
	102: "Intermediate",
	108: "Advanced",
	114: "Expert"
}

var song_records: Dictionary = {}
var session_data: Dictionary = {}
var player_options: Dictionary = {}
var player_records: Dictionary = {}
var previous_select_options: Dictionary = {}