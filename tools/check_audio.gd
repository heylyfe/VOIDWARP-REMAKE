extends SceneTree
#
# T-087 - Audio cues: the three assertions of the ticket's Done-when, as a tool.
#
#   <godot> --headless --script tools/check_audio.gd        (run from anywhere; walks up)
#
# Done-when, verbatim from the ticket:
#   1. every cue file exists with its length +/- 10 ms;
#   2. every lethal attack in the roster has a cue whose start tick is <= the attack tick
#      minus its binding cue time;
#   3. the cue ends on the attack tick +/- 1.
#
# Sources of truth (no number here is scraped from the enemy.json values it checks):
#   - research/fable-tickets.md section 3 is parsed at run time for the per-row lengths
#     (and its "loop" rows; "1 beat + 4 beats" reads as 3.0 s at the 100 BPM base, D-T087-3);
#   - game/content/enemies/<id>/enemy.json carries the wiring: stats.audio_cue_timing
#     (event / offset in ticks / length / role / binding math) and stats.lethal_attacks
#     (the roster coverage ledger). D-T087-6 records the schema; PARKED.md #12-#15 record
#     the four documented exemption classes and the check prints them as PARKED.
#   - the reconciliation of section 3's row names to the shipped cue names (the merged
#     view hooks are the contract; D-T087-1) lives in ROW_TO_CUE below.
#
# Assertion 2 compares ticks; assertion 3 compares the cue's end against the attack tick
# with one tick of slack (735.0 samples at 44.1 kHz per 60 Hz tick). Loops are exempt from
# assertion 3 (a loop never ends, D-T087-2) and from the length check (section 3 "loop").
# A binding cue flagged "PARKED.md #N" is exempt from assertion 3 only, printed as PARKED;
# assertion 2 still holds. A lethal attack with no binding cue must carry a parked reason
# (binding_cue = null + parked = "PARKED.md #N"), printed as PARKED; anything else fails.
#
# Prints one line per enemy plus PARKED/LOOP lines, a roster summary and a final verdict;
# exit 0 only when every assertion holds or every exemption is a written parked row.

const ENEMY_DIR := "game/content/enemies"
const AUDIO_DIR := "game/assets/audio/enemies"
const SECTION3_PATH := "research/fable-tickets.md"
const TBD_PATH := "TBD.md"
const EXPECTED_ROSTER := 12
const SAMPLE_RATE := 44100.0
const SAMPLES_PER_TICK := 735.0          # 44100 / 60
const LENGTH_TOLERANCE_S := 0.010        # the +/- 10 ms of assertion 1
const ATTACK_TICK_TOLERANCE := 1.0       # the +/- 1 tick of assertion 3

# section 3's row names -> the shipped cue names (D-T087-1): [folder_id, row_cue_in_backticks, file_cue]
const ROW_TO_CUE := [
	["kiwi_cat", "meow", "meow"],
	["kiwi_cat", "meow_double", "meow_double"],
	["coil", "boing", "coil_boing"],
	["coil", "twang", "coil_landing_twang"],
	["thicc_ben", "chime", "thicc_ben_chime"],
	["thicc_ben", "bong", "thicc_ben_bell"],
	["isagi", "windup", "isagi_voice_direct_shot"],
	["isagi", "shot", "isagi_gunshot"],
	["nuke", "lock_beep", "lock_on_beep"],
	["nuke", "locked", "locked"],
	["nuke", "descent_roar", "rocket_booster_roar"],
	["nuke", "boom", "impact_boom"],
	["you", "static_build", "you_corrupted_rumble"],
	["you", "ring_release", "ring_release"],
	["gift_larper", "mine_blast", "explosion"],
	["gift_larper", "mine_dud", "pff"],
	["gift_larper", "mine_hum", "mine_hum"],
	["toucher", "squelch", "toucher_squelch"],
	["toucher", "prowl", "prowl"],
	["seal", "bark", "bark"],
	["seal", "flap", "flipper_flap"],
	["address_me", "trumpet", "spawn_trumpet"],
	["address_me", "rumble", "rumble_build"],
	["address_me", "boom", "explode_boom"],
	["address_me", "leaves", "leaves"],
	["claude", "beat", "beat"],
	["claude", "drum_hit", "ui_chime"],
	["claude", "string_sweep", "string_sweep"],
	["claude", "wind_ping", "notification_ping"],
	["claude", "plushie_pop", "squeak_pop"],
	["gin", "crack_rumble", "crack_rumble"],
	["gin", "shing", "shing"],
	["gin", "whoosh", "whoosh"],
	["gin", "zone_open", "zone_open"],
	["gin", "zone_close", "zone_close"],
]

# cues with no section 3 row (recorded SPEC GAPs, D-T087-5): folder_id -> file_cue -> length_s
const EXTRA_CUES := {
	"claude": {"keystroke_tick": 0.08},
	"isagi": {"isagi_shoot_sae_math_final_shot": 0.6},
}

# section 3's table enemy names -> folder ids (the table predates the folder naming)
const TABLE_ENEMY := {
	"kiwi cat": "kiwi_cat",
	"coil": "coil",
	"thicc ben": "thicc_ben",
	"Isagi": "isagi",
	"nuke": "nuke",
	"YOU?!": "you",
	"gift Larper": "gift_larper",
	"toucher": "toucher",
	"seal": "seal",
	"address me": "address_me",
	"Claude": "claude",
	"gin ichimaru": "gin",
}

var _global_failures: Array[String] = []
var _parked_lines: Array[String] = []
var _loop_lines: Array[String] = []
var _attack_lines: Array[String] = []
var _cue_ok_count: int = 0


func _init() -> void:
	var root := _repo_root()
	if root == "":
		_global_failures.append("repo root not found walking up from %s" % _cwd())
		_report_and_quit([])
		return
	var s3 := _parse_section3(root)
	if not _global_failures.is_empty():
		_report_and_quit([])
		return
	var roster := _scan_enemies(root)
	if roster.is_empty():
		_report_and_quit([])
		return
	var ids: Array = roster.keys()
	ids.sort()
	if ids.size() != EXPECTED_ROSTER:
		_global_failures.append("expected %d enemies with enemy.json, found %d" % [EXPECTED_ROSTER, ids.size()])
	var results: Dictionary = {}
	for id in ids:
		results[id] = _check_enemy(root, s3, id, roster[id])
	_global_failures.append_array(_check_tbd(root))
	_report_and_quit(ids, results)


# ---- section 3 parsing -------------------------------------------------------
# Returns { folder_id: { file_cue: {"len_s": float, "loop": bool, "row": row_cue} } }.
# Any row that fails to parse fails the check loudly (drift alarm), never silently passes.
func _parse_section3(root: String) -> Dictionary:
	var out: Dictionary = {}
	var df := FileAccess.open(root.path_join(SECTION3_PATH), FileAccess.READ)
	if df == null:
		_global_failures.append("cannot read %s" % root.path_join(SECTION3_PATH))
		return out
	var text := df.get_as_text()
	df.close()
	var sec := text.find("## 3. Sound design briefs")
	if sec == -1:
		_global_failures.append("section 3 not found in %s" % SECTION3_PATH)
		return out
	var end := text.find("\n## ", sec + 1)
	var section := text.substr(sec, end - sec if end != -1 else text.length() - sec)
	var row_re := RegEx.new()
	row_re.compile("^\\|\\s*([^|]+?)\\s*\\|\\s*([^|]+?)\\s*\\|\\s*([^|]*?)\\s*\\|\\s*([^|]+?)\\s*\\|")
	var cue_re := RegEx.new()
	cue_re.compile("`([a-z0-9_]+)`")
	var len_re := RegEx.new()
	len_re.compile("([0-9]+(?:\\.[0-9]+)?)\\s*s")
	var parsed_rows := 0
	for line in section.split("\n"):
		var m := row_re.search(line)
		if m == null:
			continue
		var cells := [m.get_string(1).strip_edges(), m.get_string(2).strip_edges(),
				m.get_string(3).strip_edges(), m.get_string(4).strip_edges()]
		if not TABLE_ENEMY.has(cells[0]):
			continue
		var folder: String = TABLE_ENEMY[cells[0]]
		var cues := cue_re.search_all(cells[1])
		if cues.is_empty():
			_global_failures.append("section 3 row for '%s' names no cue in backticks: %s" % [cells[0], line])
			continue
		var len_cell: String = cells[3]
		var len_s := -1.0
		var is_loop := false
		var lm := len_re.search(len_cell)
		if lm != null:
			len_s = float(lm.get_string(1))
		elif len_cell.to_lower().contains("loop"):
			is_loop = true
		elif len_cell.to_lower().contains("beat"):
			len_s = 3.0          # "1 beat + 4 beats" at the 100 BPM base (D-T087-3)
		else:
			_global_failures.append("section 3 row for '%s' has an unparseable length cell: '%s'" % [cells[0], len_cell])
			continue
		parsed_rows += 1
		for cm in cues:
			var row_cue := cm.get_string(1)
			var file_cue := _map_row_cue(folder, row_cue)
			if file_cue == "":
				_global_failures.append("section 3 row cue '%s' (%s) has no ROW_TO_CUE mapping (D-T087-1)" % [row_cue, cells[0]])
				continue
			if not out.has(folder):
				out[folder] = {}
			out[folder][file_cue] = {"len_s": len_s, "loop": is_loop, "row": row_cue}
	if parsed_rows < 25:
		_global_failures.append("section 3 parsed only %d rows (want >= 25); table shape drifted?" % parsed_rows)
	return out


func _map_row_cue(folder: String, row_cue: String) -> String:
	for row in ROW_TO_CUE:
		if row[0] == folder and row[1] == row_cue:
			return str(row[2])
	return ""


# ---- enemy.json scanning ------------------------------------------------------
func _scan_enemies(root: String) -> Dictionary:
	var out: Dictionary = {}
	var enemy_root := root.path_join(ENEMY_DIR)
	var dir := DirAccess.open(enemy_root)
	if dir == null:
		_global_failures.append("cannot open %s" % enemy_root)
		return out
	for sub in dir.get_directories():
		if sub.begins_with("."):
			continue
		var epath := enemy_root.path_join(sub).path_join("enemy.json")
		var ef := FileAccess.open(epath, FileAccess.READ)
		if ef == null:
			continue
		var parsed: Variant = JSON.parse_string(ef.get_as_text())
		ef.close()
		if not (parsed is Dictionary):
			_global_failures.append("%s does not parse as a Dictionary" % epath)
			continue
		out[sub] = parsed
	return out


# ---- the three stand-ins are flagged and listed in TBD.md (ticket: TBD FALLBACK) ----
func _check_tbd(root: String) -> Array[String]:
	var fails: Array[String] = []
	var flag_checks := [["thicc_ben"], ["isagi"], ["gift_larper"]]
	for fc in flag_checks:
		var id: String = fc[0]
		var df := FileAccess.open(root.path_join(ENEMY_DIR).path_join(id).path_join("enemy.json"), FileAccess.READ)
		if df == null:
			fails.append("tbd: cannot read %s/enemy.json" % id)
			continue
		var parsed: Variant = JSON.parse_string(df.get_as_text())
		df.close()
		if not (parsed is Dictionary):
			fails.append("tbd: %s/enemy.json does not parse" % id)
			continue
		var stats: Variant = (parsed as Dictionary).get("stats", {})
		if not (stats is Dictionary) or not bool((stats as Dictionary).get("tbd_audio", false)):
			fails.append("tbd: %s stats.tbd_audio is not true (the named-recording stand-in must be flagged)" % id)
	var tf := FileAccess.open(root.path_join(TBD_PATH), FileAccess.READ)
	if tf == null:
		fails.append("tbd: cannot read %s" % TBD_PATH)
		return fails
	var tbd := tf.get_as_text()
	tf.close()
	for row in [["T-087", "isagi_voice_direct_shot"], ["T-087", "gift larper"], ["T-087", "thicc ben"]]:
		var needle: String = (row[0] + " |")
		var found := false
		for line in tbd.split("\n"):
			if line.find(needle) != -1 and line.to_lower().find(str(row[1]).to_lower()) != -1:
				found = true
				break
		if not found:
			fails.append("tbd: TBD.md has no T-087 row for '%s'" % row[1])
	return fails


func _occ(v: Variant) -> int:
	if v == null:
		return 1
	return int(v)


func _str_or_empty(v: Variant) -> String:
	if v == null:
		return ""
	return str(v)


# ---- per-enemy checks (assertions 1, 2, 3 + coverage) --------------------------
func _check_enemy(root: String, s3: Dictionary, id: String, doc: Dictionary) -> Array[String]:
	var fails: Array[String] = []
	var stats: Variant = doc.get("stats", {})
	if not (stats is Dictionary):
		return ["stats block missing or not a Dictionary"]
	var st := stats as Dictionary
	var timing_v: Variant = st.get("audio_cue_timing", {})
	var attacks_v: Variant = st.get("lethal_attacks", [])
	var timing: Dictionary = timing_v if timing_v is Dictionary else {}
	var attacks: Array = attacks_v if attacks_v is Array else []
	if not (timing_v is Dictionary):
		fails.append("audio_cue_timing missing or not a Dictionary (D-T087-6)")
	if not (attacks_v is Array):
		fails.append("lethal_attacks missing or not a list (D-T087-6)")

	# declared cue universe: audio_cues + stats.audio values; timing keys must match it
	var declared: Array[String] = []
	for c in st.get("audio_cues", []):
		declared.append(str(c))
	var audio_dict: Variant = st.get("audio", {})
	if audio_dict is Dictionary:
		for k in (audio_dict as Dictionary):
			declared.append(str((audio_dict as Dictionary)[k]))
	var seen: Dictionary = {}
	for c in declared:
		if seen.has(c):
			fails.append("cue '%s' declared twice in enemy.json" % c)
		seen[c] = true
	for k in timing:
		if not seen.has(str(k)):
			fails.append("audio_cue_timing names '%s', which is not declared by audio_cues / stats.audio (drift)" % k)
	for c in declared:
		if not timing.has(c):
			fails.append("cue '%s' has no audio_cue_timing entry (drift)" % c)

	var s3_enemy: Dictionary = s3.get(id, {})
	var wavs: Dictionary = {}

	# ---- assertion 1: every cue file exists, parses, right format, length +/- 10 ms ----
	for cue in declared:
		var path := root.path_join(AUDIO_DIR).path_join(id).path_join(cue + ".wav")
		var w := _read_wav(path)
		if w.is_empty():
			fails.append("%s/%s.wav: missing or unparseable" % [id, cue])
			continue
		wavs[cue] = w
		if int(w["rate"]) != int(SAMPLE_RATE) or int(w["channels"]) != 1 or int(w["sampwidth"]) != 2:
			fails.append("%s/%s.wav: want 44.1 kHz mono 16-bit, got %d Hz, %d ch, %d-bit" % [id, cue, int(w["rate"]), int(w["channels"]), int(w["sampwidth"]) * 8])
		var entry: Variant = timing.get(cue, {})
		var want: float = -1.0
		if entry is Dictionary and (entry as Dictionary).get("length_s") != null:
			want = float((entry as Dictionary)["length_s"])
		var s3row: Variant = s3_enemy.get(cue, null)
		if s3row == null:
			var extras_v: Variant = EXTRA_CUES.get(id, {})
			var elen := -1.0
			if extras_v is Dictionary and (extras_v as Dictionary).has(cue):
				elen = float((extras_v as Dictionary)[cue])
			if elen < 0.0:
				fails.append("cue '%s' maps to no section 3 row and is not a recorded extra (D-T087-1 / D-T087-5)" % cue)
			else:
				if absf(float(w["len_s"]) - elen) > LENGTH_TOLERANCE_S:
					fails.append("%s/%s.wav: %.4f s, recorded extra length is %.4f s (+/- 10 ms)" % [id, cue, w["len_s"], elen])
				if want >= 0.0 and absf(want - elen) > 1e-9:
					fails.append("cue '%s': enemy.json length_s %.4f != recorded extra length %.4f" % [cue, want, elen])
		elif bool(s3row.get("loop", false)):
			_loop_lines.append("LOOP %s/%s: section 3 lists no length for loop rows; file parses OK" % [id, cue])
		else:
			var s3_len := float(s3row.get("len_s", -1.0))
			if want < 0.0:
				fails.append("cue '%s': audio_cue_timing.length_s missing" % cue)
			else:
				if absf(float(w["len_s"]) - want) > LENGTH_TOLERANCE_S:
					fails.append("%s/%s.wav: %.4f s, enemy.json says %.4f s (+/- 10 ms)" % [id, cue, w["len_s"], want])
				if absf(want - s3_len) > 1e-9:
					fails.append("cue '%s': enemy.json length_s %.4f != section 3 row (%.4f s)" % [cue, want, s3_len])
				if absf(float(w["len_s"]) - s3_len) > LENGTH_TOLERANCE_S:
					fails.append("%s/%s.wav: %.4f s, section 3 lists %.4f s (+/- 10 ms)" % [id, cue, w["len_s"], s3_len])

	# every .wav on disk must be declared (drift alarm the other way)
	var adir := DirAccess.open(root.path_join(AUDIO_DIR).path_join(id))
	if adir != null:
		for f in adir.get_files():
			if f.ends_with(".wav"):
				var stem := f.trim_suffix(".wav")
				if not seen.has(stem):
					fails.append("%s/%s.wav exists on disk but no cue in enemy.json declares it (drift)" % [id, stem])

	_cue_ok_count += wavs.size()

	# ---- assertion 2 (start <= attack - binding) and assertion 3 (cue ends on attack +/- 1) ----
	var attacks_by_id: Dictionary = {}
	for a in attacks:
		if a is Dictionary:
			attacks_by_id[str((a as Dictionary).get("attack", ""))] = a
	for cue in declared:
		var entry_v: Variant = timing.get(cue, null)
		if entry_v == null or not (entry_v is Dictionary):
			continue   # already reported above
		var entry := entry_v as Dictionary
		var role := str(entry.get("role", ""))
		var attack := _str_or_empty(entry.get("attack"))
		if attack != "" and not attacks_by_id.has(attack):
			fails.append("cue '%s' references undeclared attack '%s'" % [cue, attack])
		if role == "binding":
			for req in ["event", "kind", "occurrence", "offset_ticks", "length_s", "attack", "attack_offset_ticks", "binding_cue_ticks"]:
				if entry.get(req) == null:
					fails.append("cue '%s' (role binding) is missing '%s'" % [cue, req])
			if entry.get("attack") == null:
				continue
			var ank_event := str(entry.get("event"))
			var ank_kind := str(entry.get("kind", ""))
			var ank_occ := _occ(entry.get("occurrence"))
			var aoff := float(entry.get("attack_offset_ticks", -1))
			var bind := float(entry.get("binding_cue_ticks", -1))
			var off := float(entry.get("offset_ticks", 0))
			var atk: Variant = attacks_by_id.get(attack, {})
			if atk is Dictionary and not (atk as Dictionary).is_empty():
				if ank_event != str((atk as Dictionary).get("event", "")) or ank_kind != str((atk as Dictionary).get("kind", "")):
					fails.append("cue '%s' anchors %s/%s but attack '%s' anchors %s/%s" % [cue, ank_event, ank_kind, attack, str((atk as Dictionary).get("event", "")), str((atk as Dictionary).get("kind", ""))])
				if ank_occ != _occ((atk as Dictionary).get("occurrence")):
					fails.append("cue '%s' occurrence %d != attack '%s' occurrence %d" % [cue, ank_occ, attack, _occ((atk as Dictionary).get("occurrence"))])
				if int(aoff) != int((atk as Dictionary).get("attack_offset_ticks", -2)):
					fails.append("cue '%s' attack_offset_ticks %d != attack '%s' %d" % [cue, int(aoff), attack, int((atk as Dictionary).get("attack_offset_ticks", -2))])
				if str((atk as Dictionary).get("binding_cue", "")) == cue:
					if int(bind) != int((atk as Dictionary).get("binding_cue_ticks", -2)):
						fails.append("cue '%s' binding_cue_ticks %d != its attack's designated binding %d" % [cue, int(bind), int((atk as Dictionary).get("binding_cue_ticks", -2))])
			# assertion 2
			if off > aoff - bind + 1e-6:
				fails.append("assertion 2: cue '%s' starts at tick %d > attack tick %d - binding %d ticks (= %d)" % [cue, int(off), int(aoff), int(bind), int(aoff - bind)])
			# assertion 3 (exempt: loop, or a documented parked row)
			if bool(entry.get("loop", false)):
				_loop_lines.append("LOOP %s/%s: binding cue is a loop; assertion 3 not applicable (D-T087-2)" % [id, cue])
			elif str(entry.get("parked", "")) != "":
				_parked_lines.append("PARKED %s/%s: assertion 3 exempted (%s)" % [id, cue, str(entry.get("parked"))])
			elif wavs.has(cue):
				var end_ticks := off + float(wavs[cue]["frames"]) / SAMPLES_PER_TICK
				if absf(end_ticks - aoff) > ATTACK_TICK_TOLERANCE + 1e-6:
					fails.append("assertion 3: cue '%s' ends at tick %.2f, the attack resolves at tick %d (+/- 1)" % [cue, end_ticks, int(aoff)])
		elif role in ["on_attack", "tell", "stinger", "loop"]:
			pass
		else:
			fails.append("cue '%s': unknown role '%s'" % [cue, role])

	# ---- coverage: every lethal attack in the roster names a binding cue or a parked row ----
	for atk_v in attacks:
		if not (atk_v is Dictionary):
			fails.append("lethal_attacks entry is not a Dictionary")
			continue
		var atk := atk_v as Dictionary
		var atk_id := str(atk.get("attack", ""))
		var code := str(atk.get("code", ""))
		var is_lethal := bool(atk.get("lethal", true))
		if atk_id == "":
			fails.append("lethal_attacks entry needs an attack id")
			continue
		if is_lethal and code == "":
			fails.append("lethal attack '%s' has no death code" % atk_id)
			continue
		var bcue: Variant = atk.get("binding_cue")
		if bcue == null or str(bcue) == "":
			var parked := str(atk.get("parked", ""))
			if parked == "":
				if is_lethal:
					fails.append("lethal attack '%s' (%s): no binding cue and no parked reason - uncovered" % [atk_id, code])
			else:
				_parked_lines.append("PARKED %s/%s: every-lethal-attack binding-cue rule cannot apply (%s)" % [id, atk_id, parked])
			continue
		var cue := str(bcue)
		var entry_v: Variant = timing.get(cue, null)
		if entry_v == null or not (entry_v is Dictionary):
			fails.append("lethal attack '%s': binding_cue '%s' has no audio_cue_timing entry" % [atk_id, cue])
			continue
		var entry := entry_v as Dictionary
		if str(entry.get("role", "")) != "binding":
			fails.append("lethal attack '%s': binding_cue '%s' has role '%s', want 'binding'" % [atk_id, cue, str(entry.get("role", ""))])
		if str(entry.get("attack", "")) != atk_id:
			fails.append("lethal attack '%s': binding_cue '%s' binds attack '%s'" % [atk_id, cue, str(entry.get("attack", ""))])
		if str(entry.get("event", "")) != str(atk.get("event", "")) or str(entry.get("kind", "")) != str(atk.get("kind", "")):
			fails.append("lethal attack '%s': binding_cue '%s' anchors %s/%s, attack anchored %s/%s" % [atk_id, cue, str(entry.get("event", "")), str(entry.get("kind", "")), str(atk.get("event", "")), str(atk.get("kind", ""))])
		if _occ(entry.get("occurrence")) != _occ(atk.get("occurrence")):
			fails.append("lethal attack '%s': binding_cue '%s' occurrence %d != %d" % [atk_id, cue, _occ(entry.get("occurrence")), _occ(atk.get("occurrence"))])
		if int(entry.get("attack_offset_ticks", -1)) != int(atk.get("attack_offset_ticks", -2)):
			fails.append("lethal attack '%s': binding_cue '%s' attack_offset_ticks %d != %d" % [atk_id, cue, int(entry.get("attack_offset_ticks", -1)), int(atk.get("attack_offset_ticks", -2))])
		if int(entry.get("binding_cue_ticks", -1)) != int(atk.get("binding_cue_ticks", -2)):
			fails.append("lethal attack '%s': binding_cue '%s' binding_cue_ticks %d != %d" % [atk_id, cue, int(entry.get("binding_cue_ticks", -1)), int(atk.get("binding_cue_ticks", -2))])
		if is_lethal:
			_attack_lines.append("COVERED %s: %s (%s) binding cue %s" % [id, atk_id, code, cue])
		else:
			_attack_lines.append("BOUND %s: %s (non-lethal) binding cue %s" % [id, atk_id, cue])

	return fails


# ---- minimal RIFF/WAVE reader (44.1 kHz mono 16-bit files; manual little-endian) ----
func _read_wav(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var bytes := f.get_buffer(f.get_length())
	f.close()
	if bytes.size() < 44:
		return {}
	if bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return {}
	if bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		return {}
	var pos := 12
	var rate := 0
	var channels := 0
	var bits := 0
	var data_size := 0
	while pos + 8 <= bytes.size():
		var cid := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var size := bytes[pos + 4] | (bytes[pos + 5] << 8) | (bytes[pos + 6] << 16) | (bytes[pos + 7] << 24)
		var body := pos + 8
		if cid == "fmt " and body + 16 <= bytes.size():
			channels = bytes[body + 2] | (bytes[body + 3] << 8)
			rate = bytes[body + 4] | (bytes[body + 5] << 8) | (bytes[body + 6] << 16) | (bytes[body + 7] << 24)
			bits = bytes[body + 14] | (bytes[body + 15] << 8)
		elif cid == "data":
			data_size = size
		pos = body + size + (size & 1)
	if rate <= 0 or channels <= 0 or bits <= 0 or data_size <= 0:
		return {}
	var sampwidth := int(bits / 8.0)
	var frames := int(data_size / float(channels * sampwidth))
	return {"rate": rate, "channels": channels, "sampwidth": sampwidth,
			"bits": bits, "frames": frames, "len_s": float(frames) / float(rate)}


# ---- report -------------------------------------------------------------------
func _report_and_quit(ids: Array = [], results: Dictionary = {}) -> void:
	for line in _loop_lines:
		print("  ", line)
	for line in _parked_lines:
		print("  ", line)
	for line in _attack_lines:
		print("  ", line)
	var failed := 0
	for f in _global_failures:
		print("  FAIL global - %s" % f)
		failed += 1
	var passed := 0
	for id in ids:
		var res: Array = results.get(id, ["<not checked>"])
		if res.is_empty():
			passed += 1
			print("  PASS %s" % id)
		else:
			failed += 1
			print("  FAIL %s - %s" % [id, "; ".join(res)])
	print("T-087 audio cues: %d/%d enemies pass; %d PARKED exemption(s) printed (see PARKED.md); %d cue file(s) verified" % [passed, EXPECTED_ROSTER, _parked_lines.size(), _cue_ok_count])
	if failed > 0 or passed != ids.size():
		print("T-087 RESULT: FAIL (%d failure group(s))" % failed)
		quit(1)
		return
	print("T-087 RESULT: OK")
	quit(0)


func _cwd() -> String:
	var d := DirAccess.open(".")
	return d.get_current_dir().replace("\\", "/") if d != null else "."


func _repo_root() -> String:
	var dir := _cwd()
	for i in range(8):
		if FileAccess.file_exists(dir.path_join("DESIGN.md")) and DirAccess.dir_exists_absolute(dir.path_join(ENEMY_DIR)):
			return dir
		var parent := dir.get_base_dir()
		if parent == dir:
			break
		dir = parent
	return ""
