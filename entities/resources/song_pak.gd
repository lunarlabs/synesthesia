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
        var tmp_song_data: SongData = song.duplicate_deep()

        var midi_filename = song_paths["midi"].get_file()
        writer.start_file(song_dir.path_join(midi_filename))
        var midi_file = FileAccess.open(song_paths["midi"], FileAccess.READ)
        var midi_bytes = midi_file.get_buffer(midi_file.get_length())
        writer.write_file(midi_bytes)
        writer.close_file()
        
        var click_track_filename = song_paths["click_track"].get_file()
        writer.start_file(song_dir.path_join(click_track_filename))
        var click_track_file = FileAccess.open(song_paths["click_track"], FileAccess.READ)
        var click_track_bytes = click_track_file.get_buffer(click_track_file.get_length())
        writer.write_file(click_track_bytes)
        writer.close_file()
        tmp_song_data.click_track = click_track_filename

        var preview_audio_filename = song_paths.get("preview_audio", "").get_file()
        if not preview_audio_filename.is_empty():
            writer.start_file(song_dir.path_join(preview_audio_filename))
            var preview_audio_file = FileAccess.open(song_paths["preview_audio"], FileAccess.READ)
            var preview_audio_bytes = preview_audio_file.get_buffer(preview_audio_file.get_length())
            writer.write_file(preview_audio_bytes)
            writer.close_file()
        tmp_song_data.preview_audio = preview_audio_filename

        var selection_audio_filename = song_paths.get("selection_audio", "").get_file()
        if not selection_audio_filename.is_empty():
            writer.start_file(song_dir.path_join(selection_audio_filename))
            var selection_audio_file = FileAccess.open(song_paths["selection_audio"], FileAccess.READ)
            var selection_audio_bytes = selection_audio_file.get_buffer(selection_audio_file.get_length())
            writer.write_file(selection_audio_bytes)
            writer.close_file()
        tmp_song_data.selection_audio = selection_audio_filename

        var cover_art_filename = song_paths.get("cover_art", "").get_file()
        if not cover_art_filename.is_empty():
            writer.start_file(song_dir.path_join(cover_art_filename))
            var cover_art_file = FileAccess.open(song_paths["cover_art"], FileAccess.READ)
            var cover_art_bytes = cover_art_file.get_buffer(cover_art_file.get_length())
            writer.write_file(cover_art_bytes)
            writer.close_file()
        tmp_song_data.cover_art = cover_art_filename

        for i in range(tmp_song_data.tracks.size()):
            var track: SongTrackData = tmp_song_data.tracks[i]
            var track_audio_filename = song_paths["tracks"][i].get_file()
            writer.start_file(song_dir.path_join(track_audio_filename))
            var track_audio_file = FileAccess.open(song_paths["tracks"][i], FileAccess.READ)
            var track_audio_bytes = track_audio_file.get_buffer(track_audio_file.get_length())
            writer.write_file(track_audio_bytes)
            writer.close_file()
            track.audio_file = track_audio_filename
        
        ResourceSaver.save(tmp_song_data, TEMP_SONG_DATA_PATH)
        var song_resource_name = song_dir + ".tres"
        writer.start_file(song_dir.path_join(song_resource_name))
        var song_resource_file = FileAccess.open(TEMP_SONG_DATA_PATH, FileAccess.READ)
        var song_resource_bytes = song_resource_file.get_buffer(song_resource_file.get_length())
        writer.write_file(song_resource_bytes)
        writer.close_file()
    
    DirAccess.remove_absolute(TEMP_SONG_DATA_PATH)

    #TODO: Since we don't have course resource structures yet, skip em

    var manifest_json = JSON.stringify(manifest)
    writer.start_file("manifest.json")
    writer.write_file(manifest_json.to_utf8_buffer())
    writer.close_file()

    err = writer.close()

    return err

static func import_pak(path: String) -> SynRoadSongPak:
    push_error("import_pak: Not implemented yet")
    _err = ERR_UNAVAILABLE
    return null
