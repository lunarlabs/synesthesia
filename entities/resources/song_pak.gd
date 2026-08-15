@tool

class_name SynRoadSongPak
extends Resource

static var _err = OK

@export var pak_name: String = "New SongPak"
@export var pak_banner_image: Texture2D
@export var pak_default_cover: Texture2D
@export var pak_songs: Array[SongData]
@export var pak_courses: Array[SynRoadCourse]

func export_pak(path: String):
    var writer = ZIPPacker.new()
    var err = writer.open(path)
    if err != OK:
        return err
    writer.start_file("name.txt")
    writer.write_file(pak_name.to_utf8_buffer())
    writer.close_file()
    var banner_image = pak_banner_image.get_image()
    if banner_image:
        var byte_buffer: PackedByteArray = banner_image.save_png_to_buffer()
        writer.start_file("banner.png")
        writer.write_file(byte_buffer)
        writer.close_file()
    var default_cover = pak_default_cover.get_image()
    if default_cover:
        var byte_buffer: PackedByteArray = default_cover.save_png_to_buffer()
        writer.start_file("cover.png")
        writer.write_file(byte_buffer)
        writer.close_file()
    for song: SongData in pak_songs:
        var song_dir = song.resource_path.get_file().get_basename()
        var song_paths = song.get_file_paths()
    return OK

static func import_pak(path: String) -> SynRoadSongPak:
    push_error("import_pak: Not implemented yet")
    _err = ERR_UNAVAILABLE
    return null
