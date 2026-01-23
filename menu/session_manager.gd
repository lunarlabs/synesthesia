extends Node

const LIBRARY_DB_VERSION = 1
const PLAYER_DB_VERSION = 1
const LIBRARY_DB_PATH = "res://data/library.db"
const PLAYER_DB_PATH = "res://data/player.db"

var library_db: SQLite = null
var player_db: SQLite = null
var player_attached := false

func _ready():
	library_db = SQLite.new()
	library_db.open(LIBRARY_DB_PATH)
	player_db = SQLite.new()
	player_db.open(PLAYER_DB_PATH)

func _exit_tree():
	library_db.close()
	player_db.close()
	library_db = null
	player_db = null

func _prepare_library_db():
	if not library_db:
		library_db = SQLite.new()
		library_db.path = LIBRARY_DB_PATH
		library_db.foreign_keys = true
		if library_db.open_db() == false:
			printerr("Problem opening library database!")
			return
		library_db.query("PRAGMA user_version;")
