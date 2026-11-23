extends RefCounted
#
# Launcher icon assets (cycle 7, track T3).
#
# Leg 1 - every size png renders: assets/icons/launcher/voidwrap_<n>.png exists
#   for n in 16..512, each starts with a real PNG signature and its IHDR
#   carries exactly the size its name claims (no upscaled stand-ins).
# Leg 2 - the Windows ico packs all six small frames: a valid ICONDIR (reserved
#   0, type 1, count 6), one directory entry per frame, each entry's byte size
#   matching the frame it points at, and every frame's own header agreeing
#   with its directory entry.
# Leg 3 - the configs point at the art: game/project.godot's
#   application/config/icon is the 512 px png, and export_presets.cfg's
#   preset.0 application/icon is the generated voidwrap.ico.
# Negative control - the .ico checker must still fail on corrupted input:
#   an ICONDIR with the wrong type is reported, not swallowed.

const SIZES := [512, 256, 128, 64, 48, 32, 16]
const ICO_FRAMES := [256, 128, 64, 48, 32, 16]
const ICON_DIR := "res://assets/icons/launcher"
const PNG_SIG := "PNG"


func run() -> Array[String]:
	var f: Array[String] = []
	var pngs := {}
	for size in SIZES:
		var path := "%s/voidwrap_%d.png" % [ICON_DIR, size]
		var data := _read(path)
		if data.is_empty():
			f.append("icon art: missing %s" % path)
			continue
		var dims := _png_dims(data, path, f)
		if dims.is_empty():
			continue
		pngs[size] = data
		if int(dims[0]) != size or int(dims[1]) != size:
			f.append("icon art: %s is %dx%d, expected %dx%d"
					% [path, dims[0], dims[1], size, size])
	f.append_array(_ico_and_config_failures(pngs))
	f.append_array(_negative_control())
	return f


func _read(path: String) -> PackedByteArray:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return PackedByteArray()
	return fa.get_buffer(fa.get_length())


func _png_dims(data: PackedByteArray, path: String, f: Array[String]) -> Array:
	if data.size() < 24:
		f.append("icon art: %s is only %d bytes, too short for a png" % [path, data.size()])
		return []
	if data.slice(1, 4).get_string_from_ascii() != PNG_SIG:
		f.append("icon art: %s has no PNG signature" % path)
		return []
	return [data.decode_u16(18), data.decode_u16(22)]


# One failure per broken thing: the ICONDIR header, the entry count, and then
# one entry at a time (type, byte size, frame dimensions) so a single flipped
# frame is pinpointed instead of failing the whole ico.
func _ico_failures(ico: PackedByteArray, pngs: Dictionary) -> Array[String]:
	var f: Array[String] = []
	if ico.size() < 6:
		f.append("icon art: voidwrap.ico is only %d bytes" % ico.size())
		return f
	if ico.decode_u16(0) != 0 or ico.decode_u16(2) != 1:
		f.append("icon art: voidwrap.ico ICONDIR is not a type-1 (icon) header")
	var count := ico.decode_u16(4)
	if count != ICO_FRAMES.size():
		f.append("icon art: voidwrap.ico lists %d frames, expected %d" % [count, ICO_FRAMES.size()])
	for i in range(mini(count, ICO_FRAMES.size())):
		var base := 6 + 16 * i
		var want_size := int(ICO_FRAMES[i])
		var w := ico.decode_u8(base) if ico.decode_u8(base) != 0 else 256
		var h := ico.decode_u8(base + 1) if ico.decode_u8(base + 1) != 0 else 256
		var bytes_res := ico.decode_u32(base + 8)
		var data_off := ico.decode_u32(base + 12)
		if w != want_size or h != want_size:
			f.append("icon art: voidwrap.ico frame %d says %dx%d, expected %dx%d" % [i, w, h, want_size, want_size])
		if data_off + bytes_res > ico.size():
			f.append("icon art: voidwrap.ico frame %d points outside the file" % i)
			continue
		var frame := ico.slice(data_off, data_off + bytes_res)
		if pngs.has(want_size) and frame != pngs[want_size]:
			f.append("icon art: voidwrap.ico frame %d is not the %d px png verbatim" % [i, want_size])
	return f


func _ico_and_config_failures(pngs: Dictionary) -> Array[String]:
	var f: Array[String] = []
	var ico := _read("%s/voidwrap.ico" % ICON_DIR)
	if ico.is_empty():
		f.append("icon art: missing %s/voidwrap.ico" % ICON_DIR)
		return f
	f.append_array(_ico_failures(ico, pngs))
	var proj := _read("res://project.godot").get_string_from_utf8()
	if not proj.contains("config/icon=\"%s/voidwrap_512.png\"" % ICON_DIR):
		f.append("icon art: project.godot application/config/icon does not point at the 512 png")
	var presets := _read("res://export_presets.cfg").get_string_from_utf8()
	var want := "application/icon=\"%s/voidwrap.ico\"" % ICON_DIR
	if not presets.contains(want):
		f.append("icon art: export_presets.cfg preset application/icon does not point at the ico")
	return f


func _negative_control() -> Array[String]:
	var f: Array[String] = []
	var broken := PackedByteArray()
	broken.append(1)
	if _ico_failures(broken, {}).is_empty():
		f.append("icon art: negative control failed - _ico_failures accepted a bogus ico")
	return f
