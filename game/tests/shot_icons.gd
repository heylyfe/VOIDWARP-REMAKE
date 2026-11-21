extends SceneTree
#
# Icon contact sheet (cycle 4 items 8 and 11): every upgrade icon and every curse icon,
# looked up through the SAME call the views use (view/icon_art.gd texture_for), laid out on
# the HUD's dark backdrop with each id under its icon. The ids come from the content tree
# (content/upgrades/*.json, content/curses/*.json), so a content id with no art shows as a
# red MISSING cell instead of silently dropping out. Windowed run - never --headless:
#
#   <godot> --path game --script res://tests/shot_icons.gd -- <out_dir>
#
# Writes <out_dir>/icons_00_sheet_64.png  (all icons at 64 px, ids underneath)
#        <out_dir>/icons_01_sheet_40.png  (all icons at 40 px - the HUD's own cell size)
# Prints a DIAG line (counts per kind, missing ids, icons whose opaque pixels cover less
# than 8 % of the canvas - too faint to read - and pairs of byte-identical icons). Named
# shot_*, not test_*, so tests/run_all.gd skips it. Prints "SHOT <path>" per PNG and
# "SHOTX OK" / "SHOTX FAIL <why>"; exit 1 on failure.

const IconArtScript := preload("res://view/icon_art.gd")

const SHOT_SIZE := Vector2i(1280, 720)
const BACKDROP := Color(0.0078, 0.0627, 0.0706)   # the in-run void behind the HUD rows
const KINDS := ["upgrades", "curses"]

var _out_dir := ""
var _fail := ""
var _ids: Dictionary = {}   # kind -> sorted ids


func _init() -> void:
	_run()


func _ids_for(kind: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at("res://content/%s" % kind):
		if f.ends_with(".json"):
			out.append(f.get_basename())
	out.sort()
	return out


func _run() -> void:
	await process_frame
	root.size = SHOT_SIZE
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out_dir = args[0] if args.size() >= 1 else ProjectSettings.globalize_path("res://shots_icons")
	if DirAccess.make_dir_recursive_absolute(_out_dir) != OK:
		_fail = "cannot create %s" % _out_dir
		_finish()
		return
	for k in KINDS:
		_ids[k] = _ids_for(k)
	_diag()
	var sheet := _sheet(64.0, true)
	root.add_child(sheet)
	await _shot("icons_00_sheet_64")
	sheet.free()
	sheet = _sheet(40.0, false)
	root.add_child(sheet)
	await _shot("icons_01_sheet_40")
	sheet.free()
	_finish()


func _sheet(px: float, names: bool) -> Control:
	var top := ColorRect.new()
	top.color = BACKDROP
	top.size = Vector2(SHOT_SIZE)
	var col := VBoxContainer.new()
	col.position = Vector2(12, 6)
	col.add_theme_constant_override("separation", 4)
	top.add_child(col)
	for k in KINDS:
		var ids: Array = _ids[k]
		var head := Label.new()
		head.text = "%s (%d)" % [str(k).to_upper(), ids.size()]
		head.add_theme_font_size_override("font_size", 14)
		col.add_child(head)
		var grid := GridContainer.new()
		grid.columns = 13 if names else 24
		grid.add_theme_constant_override("h_separation", 4 if names else 10)
		grid.add_theme_constant_override("v_separation", 2 if names else 10)
		col.add_child(grid)
		for id in ids:
			grid.add_child(_cell(str(k), str(id), px, names))
	return top


func _cell(kind: String, id: String, px: float, names: bool) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.custom_minimum_size = Vector2(maxf(px, 92.0) if names else px, 0)
	var tex := IconArtScript.texture_for(kind, id)
	if tex == null:
		var miss := ColorRect.new()
		miss.color = Color(1, 0.1, 0.1)
		miss.custom_minimum_size = Vector2(px, px)
		box.add_child(miss)
	else:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(px, px)
		box.add_child(tr)
	if names:
		var l := Label.new()
		l.text = id
		l.clip_text = true
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 10)
		l.add_theme_color_override("font_color", Color(0.75, 0.85, 0.9))
		box.add_child(l)
	return box


func _diag() -> void:
	var missing: PackedStringArray = []
	var faint: PackedStringArray = []
	var seen: Dictionary = {}   # image bytes hash -> first id
	var dupes: PackedStringArray = []
	var counts: PackedStringArray = []
	for k in KINDS:
		var ids: Array = _ids[k]
		counts.append("%s=%d" % [k, ids.size()])
		for id in ids:
			var tex := IconArtScript.texture_for(str(k), str(id))
			if tex == null:
				missing.append("%s/%s" % [k, id])
				continue
			var img := tex.get_image()
			if img.is_compressed():
				img.decompress()
			var opaque := 0
			for y in img.get_height():
				for x in img.get_width():
					if img.get_pixel(x, y).a > 0.5:
						opaque += 1
			var cover := float(opaque) / float(img.get_width() * img.get_height())
			if cover < 0.08:
				faint.append("%s/%s(%.0f%%)" % [k, id, cover * 100.0])
			var h := hash(img.get_data())
			if seen.has(h):
				dupes.append("%s==%s/%s" % [seen[h], k, id])
			else:
				seen[h] = "%s/%s" % [k, id]
	print("DIAG %s missing=[%s] faint=[%s] identical=[%s]" % [" ".join(counts),
			", ".join(missing), ", ".join(faint), ", ".join(dupes)])
	if not missing.is_empty():
		_fail = "%d content ids have no icon" % missing.size()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	if img == null:
		_fail = "viewport texture returned null for %s" % name
		return
	var path := _out_dir.path_join(name + ".png")
	if img.save_png(path) != OK:
		_fail = "save_png(%s) failed" % path
		return
	print("SHOT %s" % path)


func _finish() -> void:
	if _fail != "":
		print("SHOTX FAIL %s" % _fail)
		quit(1)
		return
	print("SHOTX OK")
	quit(0)
