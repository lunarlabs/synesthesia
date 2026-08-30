@tool
extends EditorPlugin

## Song Metadata Editor — a Godot editor dock that lists every SongData .tres
## file under res://song/ and lets you edit metadata, tracks, and checkpoints
## without ever navigating the filesystem.

const SONG_DIRECTORY := "user://song/"
const INSTRUMENT_OPTIONS: Array[String] = ["Drums", "Bass", "Guitar", "Synth", "Vocals", "FX"]

var dock: Control
var panel_button: Button

# ── Song List (left pane) ────────────────────────────────────────────────────
var _search_bar: LineEdit
var _song_tree: Tree
var _refresh_btn: Button

# ── Detail Editor (right pane) ───────────────────────────────────────────────
var _detail_panel: Control
var _title_edit: LineEdit
var _sub_title_edit: LineEdit
var _artist_edit: LineEdit
var _genre_edit: LineEdit
var _source_edit: LineEdit
var _desc_edit: TextEdit
var _cover_art_rect: TextureRect
var _cover_art_browse_btn: Button
var _cover_art_dialog: FileDialog
var _midi_file_edit: LineEdit
var _midi_browse_btn: Button
var _midi_dialog: FileDialog
var _fixed_bpm_check: CheckBox
var _fixed_bpm_spin: SpinBox
var _scale_fudge_spin: SpinBox
var _intro_measures_spin: SpinBox
var _playable_measures_spin: SpinBox
var _click_track_edit: LineEdit
var _click_browse_btn: Button
var _click_dialog: FileDialog
var _preview_audio_edit: LineEdit
var _preview_browse_btn: Button
var _preview_dialog: FileDialog
var _track_list: VBoxContainer
var _add_track_btn: Button
var _checkpoint_spin: SpinBox
var _add_checkpoint_btn: Button
var _remove_checkpoint_btn: Button
var _checkpoint_list: ItemList
var _save_btn: Button
var _revert_btn: Button
var _status_label: Label
var _folder_label: Label

# ── State ────────────────────────────────────────────────────────────────────
var _song_entries: Array = []          # Array of { folder, path, songdata }
var _current_entry: Dictionary = {}    # currently selected entry
var _dirty := false

# ─────────────────────────────────────────────────────────────────────────────
#  Plugin lifecycle
# ─────────────────────────────────────────────────────────────────────────────

func _enter_tree() -> void:
	dock = _build_dock()
	panel_button = add_control_to_bottom_panel(dock, "Song Metadata Editor")
	panel_button.tooltip_text = "Browse and edit SongData .tres files."
	_refresh_song_list()

func _exit_tree() -> void:
	remove_control_from_bottom_panel(dock)
	if dock:
		dock.queue_free()

# ─────────────────────────────────────────────────────────────────────────────
#  Build the entire dock UI in code (no .tscn dependency)
# ─────────────────────────────────────────────────────────────────────────────

func _build_dock() -> Control:
	var root := HSplitContainer.new()
	root.name = "SongMetadataEditorDock"
	root.anchors_preset = Control.PRESET_FULL_RECT
	root.split_offset = 280

	# ── LEFT: Song list ─────────────────────────────────────────────────────
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 240

	var top_bar := HBoxContainer.new()
	_search_bar = LineEdit.new()
	_search_bar.placeholder_text = "Filter songs…"
	_search_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_bar.clear_button_enabled = true
	_search_bar.text_changed.connect(_on_search_changed)
	top_bar.add_child(_search_bar)

	_refresh_btn = Button.new()
	_refresh_btn.text = "⟳"
	_refresh_btn.tooltip_text = "Refresh song list"
	_refresh_btn.pressed.connect(_refresh_song_list)
	top_bar.add_child(_refresh_btn)
	left.add_child(top_bar)

	_song_tree = Tree.new()
	_song_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_song_tree.hide_root = true
	_song_tree.item_selected.connect(_on_song_selected)
	left.add_child(_song_tree)
	root.add_child(left)

	# ── RIGHT: Detail editor ────────────────────────────────────────────────
	_detail_panel = _build_detail_panel()
	root.add_child(_detail_panel)

	return root


func _build_detail_panel() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ── Action bar ───────────────────────────────────────────────────────
	var action_bar := HBoxContainer.new()
	_folder_label = Label.new()
	_folder_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_folder_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	action_bar.add_child(_folder_label)
	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	action_bar.add_child(_status_label)
	_save_btn = Button.new()
	_save_btn.text = "Save"
	_save_btn.disabled = true
	_save_btn.pressed.connect(_on_save_pressed)
	action_bar.add_child(_save_btn)
	_revert_btn = Button.new()
	_revert_btn.text = "Revert"
	_revert_btn.disabled = true
	_revert_btn.pressed.connect(_on_revert_pressed)
	action_bar.add_child(_revert_btn)
	vbox.add_child(action_bar)

	# separator
	vbox.add_child(HSeparator.new())

	# ── Song Info grid ───────────────────────────────────────────────────
	var info_header := Label.new()
	info_header.text = "Song Info"
	info_header.add_theme_font_size_override("font_size", 15)
	vbox.add_child(info_header)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_title_edit = _add_grid_line_edit(grid, "Title")
	_sub_title_edit = _add_grid_line_edit(grid, "Subtitle")
	_artist_edit = _add_grid_line_edit(grid, "Artist")
	_genre_edit = _add_grid_line_edit(grid, "Genre")
	_source_edit = _add_grid_line_edit(grid, "Source")
	vbox.add_child(grid)

	# Cover Art
	var art_hbox := HBoxContainer.new()
	var art_label := Label.new()
	art_label.text = "Cover Art"
	art_hbox.add_child(art_label)
	_cover_art_rect = TextureRect.new()
	_cover_art_rect.custom_minimum_size = Vector2(64, 64)
	_cover_art_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cover_art_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art_hbox.add_child(_cover_art_rect)
	_cover_art_browse_btn = Button.new()
	_cover_art_browse_btn.text = "Browse…"
	_cover_art_browse_btn.disabled = true
	_cover_art_browse_btn.pressed.connect(_on_cover_art_browse)
	art_hbox.add_child(_cover_art_browse_btn)
	vbox.add_child(art_hbox)
	_cover_art_dialog = FileDialog.new()
	_cover_art_dialog.access = FileDialog.ACCESS_RESOURCES
	_cover_art_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_cover_art_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
	_cover_art_dialog.file_selected.connect(_on_cover_art_selected)
	vbox.add_child(_cover_art_dialog)

	# Description
	var desc_lbl := Label.new()
	desc_lbl.text = "Description"
	vbox.add_child(desc_lbl)
	_desc_edit = TextEdit.new()
	_desc_edit.custom_minimum_size.y = 60
	_desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_desc_edit.editable = false
	vbox.add_child(_desc_edit)

	vbox.add_child(HSeparator.new())

	# ── MIDI & Timing ────────────────────────────────────────────────────
	var timing_header := Label.new()
	timing_header.text = "MIDI & Timing"
	timing_header.add_theme_font_size_override("font_size", 15)
	vbox.add_child(timing_header)

	var midi_grid := GridContainer.new()
	midi_grid.columns = 3
	midi_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var midi_lbl := Label.new()
	midi_lbl.text = "MIDI File"
	midi_grid.add_child(midi_lbl)
	_midi_file_edit = LineEdit.new()
	_midi_file_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_midi_file_edit.editable = false
	midi_grid.add_child(_midi_file_edit)
	_midi_browse_btn = Button.new()
	_midi_browse_btn.text = "Browse…"
	_midi_browse_btn.disabled = true
	_midi_browse_btn.pressed.connect(_on_midi_browse)
	midi_grid.add_child(_midi_browse_btn)
	vbox.add_child(midi_grid)
	_midi_dialog = FileDialog.new()
	_midi_dialog.access = FileDialog.ACCESS_RESOURCES
	_midi_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_midi_dialog.filters = PackedStringArray(["*.mid ; MIDI Files"])
	_midi_dialog.file_selected.connect(_on_midi_selected)
	vbox.add_child(_midi_dialog)

	var timing_grid := GridContainer.new()
	timing_grid.columns = 2
	timing_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_fixed_bpm_check = CheckBox.new()
	_fixed_bpm_check.text = "Fixed BPM"
	_fixed_bpm_check.disabled = true
	timing_grid.add_child(_fixed_bpm_check)
	_fixed_bpm_spin = SpinBox.new()
	_fixed_bpm_spin.min_value = 30
	_fixed_bpm_spin.max_value = 400
	_fixed_bpm_spin.value = 120
	_fixed_bpm_spin.editable = false
	timing_grid.add_child(_fixed_bpm_spin)

	var fudge_lbl := Label.new()
	fudge_lbl.text = "Scale Fudge Factor"
	timing_grid.add_child(fudge_lbl)
	_scale_fudge_spin = SpinBox.new()
	_scale_fudge_spin.min_value = 0.5
	_scale_fudge_spin.max_value = 2.0
	_scale_fudge_spin.step = 0.1
	_scale_fudge_spin.value = 1.0
	_scale_fudge_spin.editable = false
	timing_grid.add_child(_scale_fudge_spin)

	var intro_lbl := Label.new()
	intro_lbl.text = "Lead-In Measures"
	timing_grid.add_child(intro_lbl)
	_intro_measures_spin = SpinBox.new()
	_intro_measures_spin.max_value = 500
	_intro_measures_spin.value = 4
	_intro_measures_spin.editable = false
	timing_grid.add_child(_intro_measures_spin)

	var playable_lbl := Label.new()
	playable_lbl.text = "Playable Measures"
	timing_grid.add_child(playable_lbl)
	_playable_measures_spin = SpinBox.new()
	_playable_measures_spin.min_value = 1
	_playable_measures_spin.max_value = 500
	_playable_measures_spin.value = 100
	_playable_measures_spin.editable = false
	timing_grid.add_child(_playable_measures_spin)

	vbox.add_child(timing_grid)
	vbox.add_child(HSeparator.new())

	# ── Audio ────────────────────────────────────────────────────────────
	var audio_header := Label.new()
	audio_header.text = "Audio"
	audio_header.add_theme_font_size_override("font_size", 15)
	vbox.add_child(audio_header)

	var audio_grid := GridContainer.new()
	audio_grid.columns = 3
	audio_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var click_lbl := Label.new()
	click_lbl.text = "Click Track"
	audio_grid.add_child(click_lbl)
	_click_track_edit = LineEdit.new()
	_click_track_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_click_track_edit.editable = false
	audio_grid.add_child(_click_track_edit)
	_click_browse_btn = Button.new()
	_click_browse_btn.text = "Browse…"
	_click_browse_btn.disabled = true
	_click_browse_btn.pressed.connect(_on_click_browse)
	audio_grid.add_child(_click_browse_btn)

	var preview_lbl := Label.new()
	preview_lbl.text = "Preview Audio"
	audio_grid.add_child(preview_lbl)
	_preview_audio_edit = LineEdit.new()
	_preview_audio_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_audio_edit.editable = false
	audio_grid.add_child(_preview_audio_edit)
	_preview_browse_btn = Button.new()
	_preview_browse_btn.text = "Browse…"
	_preview_browse_btn.disabled = true
	_preview_browse_btn.pressed.connect(_on_preview_browse)
	audio_grid.add_child(_preview_browse_btn)
	vbox.add_child(audio_grid)
	_click_dialog = FileDialog.new()
	_click_dialog.access = FileDialog.ACCESS_RESOURCES
	_click_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_click_dialog.filters = PackedStringArray(["*.wav, *.ogg, *.mp3 ; Audio Files"])
	_click_dialog.file_selected.connect(_on_click_selected)
	vbox.add_child(_click_dialog)
	_preview_dialog = FileDialog.new()
	_preview_dialog.access = FileDialog.ACCESS_RESOURCES
	_preview_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_preview_dialog.filters = PackedStringArray(["*.wav, *.ogg, *.mp3 ; Audio Files"])
	_preview_dialog.file_selected.connect(_on_preview_selected)
	vbox.add_child(_preview_dialog)

	vbox.add_child(HSeparator.new())

	# ── Tracks ───────────────────────────────────────────────────────────
	var track_header := HBoxContainer.new()
	var track_title := Label.new()
	track_title.text = "Instrument Tracks"
	track_title.add_theme_font_size_override("font_size", 15)
	track_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track_header.add_child(track_title)
	_add_track_btn = Button.new()
	_add_track_btn.text = "+ Add Track"
	_add_track_btn.disabled = true
	_add_track_btn.pressed.connect(_on_add_track_pressed)
	track_header.add_child(_add_track_btn)
	vbox.add_child(track_header)

	_track_list = VBoxContainer.new()
	_track_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_track_list)

	vbox.add_child(HSeparator.new())

	# ── Checkpoints ──────────────────────────────────────────────────────
	var cp_header := HBoxContainer.new()
	var cp_title := Label.new()
	cp_title.text = "Checkpoints"
	cp_title.add_theme_font_size_override("font_size", 15)
	cp_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cp_header.add_child(cp_title)

	_checkpoint_spin = SpinBox.new()
	_checkpoint_spin.max_value = 500
	_checkpoint_spin.value = 4
	_checkpoint_spin.editable = false
	cp_header.add_child(_checkpoint_spin)
	_add_checkpoint_btn = Button.new()
	_add_checkpoint_btn.text = "+"
	_add_checkpoint_btn.disabled = true
	_add_checkpoint_btn.pressed.connect(_on_add_checkpoint_pressed)
	cp_header.add_child(_add_checkpoint_btn)
	_remove_checkpoint_btn = Button.new()
	_remove_checkpoint_btn.text = "−"
	_remove_checkpoint_btn.disabled = true
	_remove_checkpoint_btn.pressed.connect(_on_remove_checkpoint_pressed)
	cp_header.add_child(_remove_checkpoint_btn)
	vbox.add_child(cp_header)

	_checkpoint_list = ItemList.new()
	_checkpoint_list.custom_minimum_size.y = 80
	_checkpoint_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_checkpoint_list)

	scroll.add_child(vbox)
	return scroll


func _add_grid_line_edit(grid: GridContainer, label_text: String) -> LineEdit:
	var lbl := Label.new()
	lbl.text = label_text
	grid.add_child(lbl)
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.editable = false
	grid.add_child(edit)
	return edit


# ─────────────────────────────────────────────────────────────────────────────
#  Song list scanning
# ─────────────────────────────────────────────────────────────────────────────

func _refresh_song_list() -> void:
	_song_entries.clear()
	var dir := DirAccess.open(SONG_DIRECTORY)
	if not dir:
		push_warning("Song Metadata Editor: cannot open %s" % SONG_DIRECTORY)
		return
	dir.list_dir_begin()
	var folder := dir.get_next()
	while folder != "":
		if dir.current_is_dir() and not folder.begins_with("."):
			var tres_path := "res://song/%s/%s.tres" % [folder, folder]
			if FileAccess.file_exists(tres_path):
				_song_entries.append({
					"folder": folder,
					"path": tres_path,
				})
		folder = dir.get_next()
	dir.list_dir_end()
	# Sort alphabetically by folder
	_song_entries.sort_custom(func(a, b): return a.folder.naturalnocasecmp_to(b.folder) < 0)
	_rebuild_tree()


func _rebuild_tree(filter: String = "") -> void:
	_song_tree.clear()
	var tree_root := _song_tree.create_item()
	for entry in _song_entries:
		if filter != "" and entry.folder.findn(filter) == -1:
			# Quick peek at loaded title if available
			if entry.has("songdata") and entry.songdata:
				if (entry.songdata as SongData).title.findn(filter) == -1 \
				and (entry.songdata as SongData).artist.findn(filter) == -1:
					continue
			else:
				continue
		var item := _song_tree.create_item(tree_root)
		# Try to show a richer label if we've already loaded it
		if entry.has("songdata") and entry.songdata:
			var sd := entry.songdata as SongData
			item.set_text(0, "%s — %s" % [sd.title, sd.artist])
		else:
			item.set_text(0, entry.folder)
		item.set_metadata(0, entry)

# ─────────────────────────────────────────────────────────────────────────────
#  Song selection & population
# ─────────────────────────────────────────────────────────────────────────────

func _on_song_selected() -> void:
	var selected := _song_tree.get_selected()
	if not selected:
		return

	if _dirty:
		# Auto-save the previous entry to avoid silent data loss
		_do_save()

	var entry: Dictionary = selected.get_metadata(0)
	var sd := ResourceLoader.load(entry.path) as SongData
	if not sd:
		_status_label.text = "Failed to load %s" % entry.path
		return
	entry["songdata"] = sd
	_current_entry = entry
	_populate_from_songdata(sd)
	# Update tree label now that we have the title
	selected.set_text(0, "%s — %s" % [sd.title, sd.artist])
	_set_dirty(false)


func _populate_from_songdata(sd: SongData) -> void:
	_folder_label.text = _current_entry.get("folder", "")

	_title_edit.text = sd.title
	_title_edit.editable = true
	_sub_title_edit.text = sd.sub_title
	_sub_title_edit.editable = true
	_artist_edit.text = sd.artist
	_artist_edit.editable = true
	_genre_edit.text = sd.genre
	_genre_edit.editable = true
	_source_edit.text = sd.source
	_source_edit.editable = true
	_desc_edit.text = sd.description
	_desc_edit.editable = true

	# Cover art
	if sd.cover_art and FileAccess.file_exists(sd.cover_art):
		var img := Image.load_from_file(sd.cover_art)
		var tex := ImageTexture.create_from_image(img)
		_cover_art_rect.texture = tex
	else:
		_cover_art_rect.texture = null
	_cover_art_browse_btn.disabled = false

	# MIDI
	_midi_file_edit.text = sd.midi_file if sd.midi_file else ""
	_midi_browse_btn.disabled = false

	# Timing
	_fixed_bpm_check.button_pressed = sd.bpm_fix
	_fixed_bpm_check.disabled = false
	_fixed_bpm_spin.value = sd.fixed_bpm
	_fixed_bpm_spin.editable = true
	_scale_fudge_spin.value = sd.scale_fudge_factor
	_scale_fudge_spin.editable = true
	_intro_measures_spin.value = sd.lead_in_measures
	_intro_measures_spin.editable = true
	_playable_measures_spin.value = sd.playable_measures
	_playable_measures_spin.editable = true

	# Audio
	_click_track_edit.text = sd.click_track if sd.click_track else ""
	_click_browse_btn.disabled = false
	_preview_audio_edit.text = sd.preview_audio if sd.preview_audio else ""
	_preview_browse_btn.disabled = false

	# Tracks
	_clear_track_rows()
	for track in sd.tracks:
		_add_track_row(track.midi_track_name, track.instrument, track.audio_file)
	_add_track_btn.disabled = false

	# Checkpoints
	_checkpoint_list.clear()
	for cp in sd.checkpoints:
		_checkpoint_list.add_item("Measure %d" % cp)
	_checkpoint_spin.editable = true
	_add_checkpoint_btn.disabled = false
	_remove_checkpoint_btn.disabled = false

	_save_btn.disabled = false
	_revert_btn.disabled = false


# ─────────────────────────────────────────────────────────────────────────────
#  Track row helpers
# ─────────────────────────────────────────────────────────────────────────────

func _clear_track_rows() -> void:
	for child in _track_list.get_children():
		child.queue_free()


func _add_track_row(midi_name: String = "", instrument_idx: int = 0, audio_file: String = "") -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var idx_label := Label.new()
	idx_label.text = "#%d" % (_track_list.get_child_count() + 1)
	idx_label.custom_minimum_size.x = 30
	row.add_child(idx_label)

	var name_edit := LineEdit.new()
	name_edit.text = midi_name
	name_edit.placeholder_text = "MIDI Track Name"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(func(_t): _set_dirty(true))
	row.add_child(name_edit)

	var inst_opt := OptionButton.new()
	for i in INSTRUMENT_OPTIONS.size():
		inst_opt.add_item(INSTRUMENT_OPTIONS[i], i)
	inst_opt.select(instrument_idx)
	inst_opt.item_selected.connect(func(_i): _set_dirty(true))
	row.add_child(inst_opt)

	var audio_edit := LineEdit.new()
	audio_edit.text = audio_file
	audio_edit.placeholder_text = "Audio file path"
	audio_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	audio_edit.text_changed.connect(func(_t): _set_dirty(true))
	row.add_child(audio_edit)

	var browse_btn := Button.new()
	browse_btn.text = "…"
	browse_btn.tooltip_text = "Browse for audio file"
	var fd := FileDialog.new()
	fd.access = FileDialog.ACCESS_RESOURCES
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.filters = PackedStringArray(["*.wav, *.ogg, *.mp3 ; Audio Stems"])
	if _current_entry.has("folder"):
		fd.current_dir = "res://song/%s" % _current_entry.folder
	fd.file_selected.connect(func(path: String):
		audio_edit.text = path
		_set_dirty(true)
	)
	row.add_child(fd)
	browse_btn.pressed.connect(func():
		fd.popup_centered(Vector2i(800, 500))
	)
	row.add_child(browse_btn)

	var remove_btn := Button.new()
	remove_btn.text = "✕"
	remove_btn.tooltip_text = "Remove track"
	remove_btn.pressed.connect(func():
		row.queue_free()
		_set_dirty(true)
		# Re-number after a frame
		_renumber_tracks.call_deferred()
	)
	row.add_child(remove_btn)

	_track_list.add_child(row)


func _renumber_tracks() -> void:
	var idx := 1
	for child in _track_list.get_children():
		if child is HBoxContainer:
			var lbl := child.get_child(0) as Label
			if lbl:
				lbl.text = "#%d" % idx
				idx += 1


# ─────────────────────────────────────────────────────────────────────────────
#  Callbacks
# ─────────────────────────────────────────────────────────────────────────────

func _on_search_changed(text: String) -> void:
	_rebuild_tree(text)


func _on_add_track_pressed() -> void:
	_add_track_row()
	_set_dirty(true)


func _on_add_checkpoint_pressed() -> void:
	var m := int(_checkpoint_spin.value)
	for i in _checkpoint_list.item_count:
		var existing := int(_checkpoint_list.get_item_text(i).get_slice(" ", 1))
		if existing == m:
			_status_label.text = "Checkpoint at measure %d already exists." % m
			return
	_checkpoint_list.add_item("Measure %d" % m)
	_set_dirty(true)
	_sort_checkpoint_list()


func _on_remove_checkpoint_pressed() -> void:
	var sel := _checkpoint_list.get_selected_items()
	if sel.size() > 0:
		_checkpoint_list.remove_item(sel[0])
		_set_dirty(true)


func _sort_checkpoint_list() -> void:
	var measures: Array[int] = []
	for i in _checkpoint_list.item_count:
		measures.append(int(_checkpoint_list.get_item_text(i).get_slice(" ", 1)))
	measures.sort()
	_checkpoint_list.clear()
	for m in measures:
		_checkpoint_list.add_item("Measure %d" % m)


# ── File dialog callbacks ───────────────────────────────────────────────────

func _on_cover_art_browse() -> void:
	_cover_art_dialog.popup_centered(Vector2i(800, 500))

func _on_cover_art_selected(path: String) -> void:
	var tex = load(path) as Texture2D
	if tex:
		_cover_art_rect.texture = tex
		_set_dirty(true)

func _on_midi_browse() -> void:
	_midi_dialog.popup_centered(Vector2i(800, 500))

func _on_midi_selected(path: String) -> void:
	_midi_file_edit.text = path
	_set_dirty(true)

func _on_click_browse() -> void:
	_click_dialog.popup_centered(Vector2i(800, 500))

func _on_click_selected(path: String) -> void:
	_click_track_edit.text = path
	_set_dirty(true)

func _on_preview_browse() -> void:
	_preview_dialog.popup_centered(Vector2i(800, 500))

func _on_preview_selected(path: String) -> void:
	_preview_audio_edit.text = path
	_set_dirty(true)


# ─────────────────────────────────────────────────────────────────────────────
#  Save / Revert
# ─────────────────────────────────────────────────────────────────────────────

func _on_save_pressed() -> void:
	_do_save()


func _do_save() -> void:
	if _current_entry.is_empty():
		return
	var sd := _current_entry.songdata as SongData
	if not sd:
		return

	# ── Gather from GUI ──────────────────────────────────────────────────
	sd.title = _title_edit.text
	sd.sub_title = _sub_title_edit.text
	sd.artist = _artist_edit.text
	sd.genre = _genre_edit.text
	sd.source = _source_edit.text
	sd.description = _desc_edit.text

	# Cover art
	if _cover_art_rect.texture:
		var img := Image.load_from_file(sd.cover_art)
		var tex := ImageTexture.create_from_image(img)
		_cover_art_rect.texture = tex

	# MIDI
	sd.midi_file = _midi_file_edit.text if _midi_file_edit.text != "" else null

	# Timing
	sd.bpm_fix = _fixed_bpm_check.button_pressed
	sd.fixed_bpm = _fixed_bpm_spin.value
	sd.scale_fudge_factor = _scale_fudge_spin.value
	sd.lead_in_measures = int(_intro_measures_spin.value)
	sd.playable_measures = int(_playable_measures_spin.value)

	# Audio
	sd.click_track = _click_track_edit.text if _click_track_edit.text != "" else ""
	sd.preview_audio = _preview_audio_edit.text if _preview_audio_edit.text != "" else ""

	# Tracks
	sd.tracks.clear()
	for child in _track_list.get_children():
		if not child is HBoxContainer:
			continue
		var hbox := child as HBoxContainer
		# Layout: idx_label, name_edit, inst_opt, audio_edit, file_dialog, browse_btn, remove_btn
		var name_edit := hbox.get_child(1) as LineEdit
		var inst_opt := hbox.get_child(2) as OptionButton
		var audio_edit := hbox.get_child(3) as LineEdit
		var trackdata := SongTrackData.new()
		trackdata.midi_track_name = name_edit.text
		trackdata.instrument = inst_opt.selected
		trackdata.audio_file = audio_edit.text
		sd.tracks.append(trackdata)

	# Checkpoints
	sd.checkpoints.clear()
	for i in _checkpoint_list.item_count:
		var measure := int(_checkpoint_list.get_item_text(i).get_slice(" ", 1))
		sd.checkpoints.append(measure)

	# ── Write to disk ────────────────────────────────────────────────────
	var err := ResourceSaver.save(sd, _current_entry.path)
	if err == OK:
		_status_label.text = "Saved ✓"
		_status_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
		# Update tree label
		var selected := _song_tree.get_selected()
		if selected:
			selected.set_text(0, "%s — %s" % [sd.title, sd.artist])
	else:
		_status_label.text = "Save failed: %s" % error_string(err)
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))

	_set_dirty(false)


func _on_revert_pressed() -> void:
	if _current_entry.is_empty():
		return
	# Reload from disk
	var sd := ResourceLoader.load(_current_entry.path) as SongData
	if sd:
		_current_entry["songdata"] = sd
		_populate_from_songdata(sd)
		_status_label.text = "Reverted"
		_status_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
		_set_dirty(false)


func _set_dirty(dirty: bool) -> void:
	_dirty = dirty
	if _save_btn:
		_save_btn.text = "Save*" if dirty else "Save"
