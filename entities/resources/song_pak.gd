@tool

class_name SynRoadSongPak
extends Resource

static var _err = OK

@export var pak_name: String
@export var pak_image: Texture2D
@export_file_path("*.tres") var pak_songs: PackedStringArray

static func export_pak(pak: SynRoadSongPak, path: String) -> bool:
    push_error("export_pak: Not implemented yet")
    _err = ERR_UNAVAILABLE
    return false

static func import_pak(path: String) -> SynRoadSongPak:
    push_error("import_pak: Not implemented yet")
    _err = ERR_UNAVAILABLE
    return null
