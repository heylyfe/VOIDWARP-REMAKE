extends SceneTree
#
# game/tools/check_anim_data.gd - proves the T-083 anim blocks (ticket T-083, headless).
#
#   tools\godot\godot.exe --headless --path game --script res://tools/check_anim_data.gd -- [enemy_id ...]
#
# With no arguments, every enemy in the roster is checked. With arguments, only those ids
# are checked (so both halves of the roster can be validated independently).
#
# For each enemy this proves, against the section 1.x tables of research/fable-tickets.md
# (the animation tables ARE the spec - one section per enemy, 1.1 through 1.12):
#   1. content/enemies/<id>/sprites.json parses and carries an "anim" block with the right
#      section number;
#   2. every state of that enemy's table exists, with the table's frames (by spec frame
#      name, in table order), the table's loop flag, and the table's tick counts
#      (ticks_per_frame / explicit tick_ranges / total_ticks - a state whose holding tick
#      the table does not bound carries total_ticks: null);
#   3. no unexpected states (the anim block is one entry per table row, no more);
#   4. every referenced frame file exists on disk (relative to the enemy folder), and the
#      frames list has one entry per spec frame (repeats allowed for TBD placeholders);
#   5. every entry carries an effect with a non-empty name and a params dictionary.
#
# The checker hardcodes the binding numbers from the tables - it never reads the markdown,
# so a spec edit fails loudly here instead of silently re-passing. If a table changes, this
# file changes with it (same commit).
#
# Prints "PASS <id> (<n> states)" or "FAIL <id>: <message>" per enemy, then
# "ANIM-DATA <p> passed <f> failed". Exit code 0 iff f == 0.

const CONTENT_REL := "content/enemies"

# Expected tables. Per state: spec_frames (table order), loop, total_ticks (null when the
# table bounds no duration), ticks_per_frame (null when the table gives explicit ranges or
# no per-frame ticks), tick_ranges (null unless the table gives explicit ranges; each entry
# is [frame, first_tick, last_tick], state-local), plus optional repeat_every_ticks and fps.
const EXPECTED := {
	"kiwi_cat": {
		"section": "1.1",
		"states": {
			"spawn": {"spec_frames": ["kiwicat_00"], "loop": false, "total_ticks": 30, "ticks_per_frame": 30.0, "tick_ranges": null},
			"idle_chase": {"spec_frames": ["kiwicat_00"], "loop": true, "total_ticks": null, "ticks_per_frame": null, "tick_ranges": null},
			"telegraph": {"spec_frames": ["kiwicat_00"], "loop": false, "total_ticks": 12, "ticks_per_frame": 12.0, "tick_ranges": null, "repeat_every_ticks": 180},
			"attack": {"spec_frames": [], "loop": false, "total_ticks": null, "ticks_per_frame": null, "tick_ranges": null},
			"recover": {"spec_frames": [], "loop": false, "total_ticks": null, "ticks_per_frame": null, "tick_ranges": null},
		},
	},
	"coil": {
		"section": "1.2",
		"states": {
			"spawn": {"spec_frames": ["coil_02"], "loop": false, "total_ticks": 30, "ticks_per_frame": 30.0, "tick_ranges": null},
			"idle": {"spec_frames": ["coil_01", "coil_02"], "loop": true, "total_ticks": null, "ticks_per_frame": 30.0, "tick_ranges": null},
			"telegraph": {"spec_frames": ["coil_02", "coil_01", "coil_00"], "loop": false, "total_ticks": 36, "ticks_per_frame": 12.0, "tick_ranges": [["coil_02", 0, 11], ["coil_01", 12, 23], ["coil_00", 24, 35]]},
			"attack_flight": {"spec_frames": ["coil_03", "coil_04", "coil_03"], "loop": false, "total_ticks": 165, "ticks_per_frame": null, "tick_ranges": [["coil_03", 0, 20], ["coil_04", 21, 144], ["coil_03", 145, 164]]},
			"attack_landing": {"spec_frames": ["coil_00"], "loop": false, "total_ticks": null, "ticks_per_frame": null, "tick_ranges": null},
			"recover": {"spec_frames": ["coil_00", "coil_01"], "loop": false, "total_ticks": 24, "ticks_per_frame": 12.0, "tick_ranges": null},
		},
	},
	"thicc_ben": {
		"section": "1.3",
		"states": {
			"spawn": {"spec_frames": ["thiccben_00"], "loop": false, "total_ticks": 30, "ticks_per_frame": 30.0, "tick_ranges": null},
			"idle": {"spec_frames": ["thiccben_00"], "loop": true, "total_ticks": null, "ticks_per_frame": null, "tick_ranges": null},
			"telegraph": {"spec_frames": [], "loop": false, "total_ticks": 75, "ticks_per_frame": null, "tick_ranges": null},
			"attack_arrival": {"spec_frames": ["thiccben_00"], "loop": false, "total_ticks": null, "ticks_per_frame": null, "tick_ranges": null},
			"attack_ring": {"spec_frames": ["thiccben_00"], "loop": false, "total_ticks": 18, "ticks_per_frame": 18.0, "tick_ranges": null},
			"recover": {"spec_frames": ["thiccben_00"], "loop": false, "total_ticks": null, "ticks_per_frame": null, "tick_ranges": null},
		},
	},
	"isagi": {
		"section": "1.4",
		"states": {
			"spawn": {"spec_frames": ["isagi_idle_00"], "loop": false, "total_ticks": 30, "ticks_per_frame": 30.0, "tick_ranges": null},
			"idle": {"spec_frames": ["isagi_idle_00"], "loop": true, "total_ticks": null, "ticks_per_frame": null, "tick_ranges": null},
			"telegraph": {"spec_frames": ["isagi_idle_00"], "loop": false, "total_ticks": 72, "ticks_per_frame": 72.0, "tick_ranges": null},
			"attack": {"spec_frames": ["isagi_shoot_00"], "loop": false, "total_ticks": 30, "ticks_per_frame": null, "tick_ranges": [["isagi_shoot_00", 0, 30]]},
			"recover": {"spec_frames": ["isagi_idle_00"], "loop": true, "total_ticks": 150, "ticks_per_frame": null, "tick_ranges": null},
		},
	},
	"nuke": {
		"section": "1.5",
		"states": {
			"spawn": {"spec_frames": [], "loop": false, "total_ticks": null, "ticks_per_frame": null, "tick_ranges": null},
			"telegraph_tracking": {"spec_frames": [], "loop": true, "total_ticks": 150, "ticks_per_frame": null, "tick_ranges": null},
			"telegraph_locked": {"spec_frames": [], "loop": false, "total_ticks": 90, "ticks_per_frame": null, "tick_ranges": null},
			"attack_descent": {"spec_frames": ["nuke_00", "nuke_01", "nuke_02", "nuke_03"], "loop": true, "total_ticks": 90, "ticks_per_frame": 5.0, "tick_ranges": null, "fps": 12.0},
			"attack_explosion": {"spec_frames": [], "loop": false, "total_ticks": 24, "ticks_per_frame": null, "tick_ranges": null},
			"recover": {"spec_frames": [], "loop": false, "total_ticks": 300, "ticks_per_frame": null, "tick_ranges": null},
		},
	},
	"gift_larper": {
		"section": "1.7",
		"states": {
			"spawn": {"spec_frames": ["larper_00"], "loop": false, "total_ticks": null, "ticks_per_frame": null, "tick_ranges": null},
			"idle": {"spec_frames": ["larper_00", "larper_01", "larper_02", "larper_03", "larper_04"], "loop": true, "total_ticks": null, "ticks_per_frame": 48.0, "tick_ranges": null},
			"telegraph": {"spec_frames": [], "loop": false, "total_ticks": null, "ticks_per_frame": null, "tick_ranges": null},
			"attack_detonation": {"spec_frames": [], "loop": false, "total_ticks": 18, "ticks_per_frame": null, "tick_ranges": null},
			"defused": {"spec_frames": ["larper_00"], "loop": false, "total_ticks": 24, "ticks_per_frame": null, "tick_ranges": null},
		},
	},
	"toucher": {
		"section": "1.8",
		"states": {
			"spawn": {"spec_frames": ["toucher_00"], "loop": false, "total_ticks": 30, "ticks_per_frame": 30.0, "tick_ranges": null},
			"idle_chase": {"spec_frames": ["toucher_00", "toucher_01", "toucher_02"], "loop": true, "total_ticks": null, "ticks_per_frame": 6.0, "tick_ranges": null, "fps": 10.0},
			"telegraph": {"spec_frames": ["toucher_00", "toucher_01", "toucher_02"], "loop": false, "total_ticks": 18, "ticks_per_frame": 3.0, "tick_ranges": null, "fps": 20.0, "repeat_every_ticks": 120},
			"attack_infect": {"spec_frames": ["toucher_02"], "loop": false, "total_ticks": null, "ticks_per_frame": null, "tick_ranges": null},
			"attack_touch": {"spec_frames": [], "loop": false, "total_ticks": null, "ticks_per_frame": null, "tick_ranges": null},
			"recover": {"spec_frames": [], "loop": false, "total_ticks": null, "ticks_per_frame": null, "tick_ranges": null},
		},
	},
	"seal": {
		"section": "1.9",
		"states": {
			"spawn": {"spec_frames": ["seal_00"], "loop": false, "total_ticks": 30, "ticks_per_frame": 30.0, "tick_ranges": null},
			"idle_flap": {"spec_frames": ["seal_02", "seal_03"], "loop": true, "total_ticks": null, "ticks_per_frame": 9.0, "tick_ranges": null},
			"telegraph": {"spec_frames": ["seal_01"], "loop": false, "total_ticks": 45, "ticks_per_frame": 45.0, "tick_ranges": null},
			"attack": {"spec_frames": ["seal_01"], "loop": false, "total_ticks": 60, "ticks_per_frame": 4.0, "tick_ranges": null, "fps": 15.0},
			"recover": {"spec_frames": ["seal_00"], "loop": false, "total_ticks": 45, "ticks_per_frame": 45.0, "tick_ranges": null},
		},
	},
	"address_me": {
		"section": "1.10",
		"states": {
			"spawn": {"spec_frames": ["addressme_00"], "loop": false, "total_ticks": 12, "ticks_per_frame": 12.0, "tick_ranges": null},
			"telegraph": {"spec_frames": ["addressme_00"], "loop": true, "total_ticks": 300, "ticks_per_frame": null, "tick_ranges": null},
			"leaves": {"spec_frames": ["addressme_00"], "loop": false, "total_ticks": 18, "ticks_per_frame": 18.0, "tick_ranges": null},
			"attack": {"spec_frames": ["addressme_01"], "loop": false, "total_ticks": 24, "ticks_per_frame": 24.0, "tick_ranges": null},
			"recover": {"spec_frames": [], "loop": false, "total_ticks": null, "ticks_per_frame": null, "tick_ranges": null},
		},
	},
	"claude": {
		"section": "1.11",
		"states": {
			"spawn": {"spec_frames": ["claude_00"], "loop": false, "total_ticks": 30, "ticks_per_frame": 30.0, "tick_ranges": null},
			"idle": {"spec_frames": ["claude_00"], "loop": true, "total_ticks": null, "ticks_per_frame": null, "tick_ranges": null},
			"telegraph_drums": {"spec_frames": ["claude_00"], "loop": false, "total_ticks": null, "ticks_per_frame": null, "tick_ranges": null},
			"attack_drums": {"spec_frames": ["claude_00"], "loop": false, "total_ticks": null, "ticks_per_frame": null, "tick_ranges": null},
			"telegraph_strings": {"spec_frames": ["claude_00"], "loop": false, "total_ticks": 36, "ticks_per_frame": 36.0, "tick_ranges": null},
			"attack_strings": {"spec_frames": ["claude_00"], "loop": false, "total_ticks": null, "ticks_per_frame": null, "tick_ranges": null},
			"attack_wind": {"spec_frames": ["claude_00"], "loop": false, "total_ticks": null, "ticks_per_frame": null, "tick_ranges": null},
			"deadline": {"spec_frames": ["claude_00"], "loop": true, "total_ticks": null, "ticks_per_frame": null, "tick_ranges": null},
			"plushie_idle": {"spec_frames": ["plushie_00", "plushie_01", "plushie_02"], "loop": true, "total_ticks": null, "ticks_per_frame": 10.0, "tick_ranges": null, "fps": 6.0},
		},
	},
	"gin": {
		"section": "1.12",
		"states": {
			"spawn": {"spec_frames": ["gin_idle_00"], "loop": false, "total_ticks": 30, "ticks_per_frame": 30.0, "tick_ranges": null},
			"idle": {"spec_frames": ["gin_idle_00"], "loop": true, "total_ticks": null, "ticks_per_frame": null, "tick_ranges": null},
			"telegraph": {"spec_frames": ["gin_idle_00"], "loop": false, "total_ticks": 120, "ticks_per_frame": null, "tick_ranges": null},
			"attack_launch": {"spec_frames": ["gin_launch_00"], "loop": false, "total_ticks": 18, "ticks_per_frame": null, "tick_ranges": null},
			"attack_void_zone": {"spec_frames": [], "loop": false, "total_ticks": 600, "ticks_per_frame": null, "tick_ranges": null},
			"recover": {"spec_frames": ["gin_idle_00"], "loop": true, "total_ticks": null, "ticks_per_frame": null, "tick_ranges": null},
		},
	},
	"you": {
		"section": "1.6",
		"states": {
			"spawn": {"spec_frames": ["you_00"], "loop": false, "total_ticks": 30, "ticks_per_frame": 30.0, "tick_ranges": null},
			"idle_chase": {"spec_frames": ["you_00", "you_01", "you_02", "you_03", "you_04"], "loop": true, "total_ticks": null, "ticks_per_frame": 7.5, "tick_ranges": null, "fps": 8.0},
			"telegraph": {"spec_frames": ["you_00", "you_01", "you_02", "you_03", "you_04"], "loop": true, "total_ticks": 90, "ticks_per_frame": 3.75, "tick_ranges": null, "fps": 16.0},
			"attack": {"spec_frames": ["you_04"], "loop": false, "total_ticks": null, "ticks_per_frame": null, "tick_ranges": null},
			"recover": {"spec_frames": ["you_00", "you_01", "you_02", "you_03", "you_04"], "loop": true, "total_ticks": 240, "ticks_per_frame": 7.5, "tick_ranges": null, "fps": 8.0},
		},
	},
}


func _null_or_float(v) -> Variant:
	if v == null:
		return null
	return float(v)


func _floats_equal(a, b) -> bool:
	if a == null and b == null:
		return true
	if a == null or b == null:
		return false
	return is_equal_approx(float(a), float(b))


func _check_ranges(actual, expected) -> bool:
	if expected == null:
		return actual == null
	if not (actual is Array):
		return false
	if actual.size() != expected.size():
		return false
	for i in range(expected.size()):
		var a = actual[i]
		var e: Array = expected[i]
		if not (a is Array) or a.size() != 3:
			return false
		if str(a[0]) != str(e[0]):
			return false
		if not is_equal_approx(float(a[1]), float(e[1])):
			return false
		if not is_equal_approx(float(a[2]), float(e[2])):
			return false
	return true


func _check_enemy(game_dir: String, enemy_id: String) -> Array[String]:
	var failures: Array[String] = []
	var exp: Dictionary = EXPECTED[enemy_id]
	var json_path: String = game_dir + "/" + CONTENT_REL + "/" + enemy_id + "/sprites.json"
	if not FileAccess.file_exists(json_path):
		return ["sprites.json missing at %s" % json_path]
	var text := FileAccess.get_file_as_string(json_path)
	var doc = JSON.parse_string(text)
	if doc == null or not (doc is Dictionary):
		return ["sprites.json does not parse as a dictionary"]
	var anim = doc.get("anim", null)
	if anim == null or not (anim is Dictionary):
		return ["no 'anim' block (T-083) in sprites.json"]
	var section := str(anim.get("section", ""))
	if section != str(exp["section"]):
		failures.append("anim.section '%s' != table section '%s'" % [section, str(exp["section"])])
	var states = anim.get("states", null)
	if states == null or not (states is Dictionary):
		return failures + ["anim.states missing or not a dictionary"]
	# no unexpected states: one entry per table row, no more
	for key in states.keys():
		if not exp["states"].has(key):
			failures.append("unexpected state '%s' (not in the table)" % str(key))
	var enemy_dir: String = game_dir + "/" + CONTENT_REL + "/" + enemy_id
	for state_id in exp["states"].keys():
		var want: Dictionary = exp["states"][state_id]
		if not states.has(state_id):
			failures.append("missing state '%s'" % str(state_id))
			continue
		var got = states[state_id]
		if not (got is Dictionary):
			failures.append("state '%s' is not a dictionary" % str(state_id))
			continue
		# spec frames, in table order
		var sf = got.get("spec_frames", null)
		if not (sf is Array):
			failures.append("state '%s': spec_frames missing or not an array" % str(state_id))
			sf = []
		var want_sf: Array = want["spec_frames"]
		if sf.size() != want_sf.size():
			failures.append("state '%s': spec_frames %s != table frames %s" % [str(sf), str(want_sf)])
		else:
			for i in range(want_sf.size()):
				if str(sf[i]) != str(want_sf[i]):
					failures.append("state '%s': spec_frames[%d] '%s' != '%s'" % [str(state_id), i, str(sf[i]), str(want_sf[i])])
					break
		# the files on disk
		var fr = got.get("frames", null)
		if not (fr is Array):
			failures.append("state '%s': frames missing or not an array" % str(state_id))
			fr = []
		if fr.size() != want_sf.size():
			failures.append("state '%s': %d frame entries for %d spec frames" % [str(state_id), fr.size(), want_sf.size()])
		for i in range(fr.size()):
			var rel := str(fr[i])
			if rel == "":
				failures.append("state '%s': frames[%d] is empty" % [str(state_id), i])
				continue
			if not FileAccess.file_exists(enemy_dir + "/" + rel):
				failures.append("state '%s': frame file not on disk: %s" % [str(state_id), rel])
		# loop flag
		if bool(got.get("loop", false)) != bool(want["loop"]):
			failures.append("state '%s': loop %s != table loop %s" % [str(state_id), str(got.get("loop")), str(want["loop"])])
		# tick counts
		if not _floats_equal(_null_or_float(got.get("total_ticks", null)), _null_or_float(want["total_ticks"])):
			failures.append("state '%s': total_ticks %s != table %s" % [str(state_id), str(got.get("total_ticks", null)), str(want["total_ticks"])])
		if not _floats_equal(_null_or_float(got.get("ticks_per_frame", null)), _null_or_float(want["ticks_per_frame"])):
			failures.append("state '%s': ticks_per_frame %s != table %s" % [str(state_id), str(got.get("ticks_per_frame", null)), str(want["ticks_per_frame"])])
		if not _check_ranges(got.get("tick_ranges", null), want["tick_ranges"]):
			failures.append("state '%s': tick_ranges %s != table %s" % [str(state_id), str(got.get("tick_ranges", null)), str(want["tick_ranges"])])
		if want.has("repeat_every_ticks"):
			if not _floats_equal(_null_or_float(got.get("repeat_every_ticks", null)), float(want["repeat_every_ticks"])):
				failures.append("state '%s': repeat_every_ticks %s != table %s" % [str(state_id), str(got.get("repeat_every_ticks", null)), str(want["repeat_every_ticks"])])
		if want.has("fps"):
			if not _floats_equal(_null_or_float(got.get("fps", null)), float(want["fps"])):
				failures.append("state '%s': fps %s != table %s" % [str(state_id), str(got.get("fps", null)), str(want["fps"])])
		# effect: a name and a params dictionary
		var effect = got.get("effect", null)
		if effect == null or not (effect is Dictionary):
			failures.append("state '%s': effect missing or not a dictionary" % str(state_id))
		else:
			if str(effect.get("name", "")) == "":
				failures.append("state '%s': effect.name is empty" % str(state_id))
			if not (effect.get("params", null) is Dictionary):
				failures.append("state '%s': effect.params missing or not a dictionary" % str(state_id))
	# frame_map values, when present, must exist on disk
	var fmap = anim.get("frame_map", null)
	if fmap is Dictionary:
		for k in fmap.keys():
			var rel := str(fmap[k])
			if not FileAccess.file_exists(enemy_dir + "/" + rel):
				failures.append("frame_map['%s'] not on disk: %s" % [str(k), rel])
	# spec frames named in frame_map must be a subset of the section's frames
	return failures


func _init() -> void:
	var game_dir := ProjectSettings.globalize_path("res://")
	if game_dir.ends_with("/"):
		game_dir = game_dir.substr(0, game_dir.length() - 1)
	var ids: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		var id := str(arg)
		if id != "":
			ids.append(id)
	if ids.is_empty():
		for k in EXPECTED.keys():
			ids.append(str(k))
		ids.sort()
	var passed := 0
	var failed := 0
	for id in ids:
		if not EXPECTED.has(id):
			print("FAIL %s: unknown enemy id (known: %s)" % [id, ", ".join(EXPECTED.keys())])
			failed += 1
			continue
		var failures := _check_enemy(game_dir, id)
		if failures.is_empty():
			passed += 1
			print("PASS %s (%d states)" % [id, (EXPECTED[id]["states"] as Dictionary).size()])
		else:
			failed += 1
			for msg in failures:
				print("FAIL %s: %s" % [id, msg])
	print("ANIM-DATA %d passed %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

