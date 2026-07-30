class_name SynRoadSongPak
extends Resource

static var _err = OK


static func export_pak(pak: SynRoadSongPak, path: String) -> bool:
    push_error("export_pak: Not implemented yet")
    _err = ERR_UNAVAILABLE
    return false

static func import_pak(path: String) -> SynRoadSongPak:
    push_error("import_pak: Not implemented yet")
    _err = ERR_UNAVAILABLE
    return null
