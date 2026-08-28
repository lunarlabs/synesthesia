@tool

class_name SynRoadSongPak
extends Resource

const TEMP_SONG_DATA_PATH = "res://temp_song_data.tres"

static var _err = OK

@export var pak_name: String = "New SongPak"
@export var pak_banner_image: String = ""
@export var pak_default_cover: String = ""
@export var pak_songs: Array[SongData]
@export var pak_courses: Array[SynRoadCourse]

var manifest: Dictionary = {
    "name": pak_name,
    "songs": [],
    "courses": [],
}

func export_pak(path: String):
    var writer = ZIPPacker.new()
    var err = writer.open(path)
    if err != OK:
        return err
    writer.start_file("name.txt")
    writer.write_file(pak_name.to_utf8_buffer())
    writer.close_file()
    if FileAccess.file_exists(pak_banner_image):
        manifest["banner"] = "banner.png"
        writer.start_file("banner.png")
        var banner_file = FileAccess.open(pak_banner_image, FileAccess.READ)
        var banner_bytes = banner_file.get_buffer(banner_file.get_length())
        writer.write_file(banner_bytes)
        writer.close_file()
    if FileAccess.file_exists(pak_default_cover):
        manifest["default_cover"] = "cover.png"
        writer.start_file("cover.png")
        var cover_file = FileAccess.open(pak_default_cover, FileAccess.READ)
        var cover_bytes = cover_file.get_buffer(cover_file.get_length())
        writer.write_file(cover_bytes)
        writer.close_file()
    for song: SongData in pak_songs:
        var song_dir = song.resource_path.get_file().get_basename()
        var song_paths = song.get_file_paths()
        manifest["songs"].append(song_dir)
    return OK

static func import_pak(path: String) -> SynRoadSongPak:
    push_error("import_pak: Not implemented yet")
    _err = ERR_UNAVAILABLE
    return null
