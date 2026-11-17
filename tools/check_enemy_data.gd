extends SceneTree
#
# T-073 - Enemy data pass: compare every section-5 data field of each shipped
# content/enemies/<id>/enemy.json with the tables in DESIGN.md section 5.
#
#   <godot> --headless --script tools/check_enemy_data.gd
#
# DESIGN.md is read at run time; no table number is hardcoded here. Parsed:
#   - the SR-2 body-size table (height / diameter per enemy; coil's squashed/extended cell,
#     address me's em-dash diameter),
#   - the SR-5 pursuit-ceiling table (the "kitten (The Litter)" row is not one of the 12),
#   - the SR-5 prose burst bound ("may reach 1.00 x base run speed" - the bound is parsed;
#     its absence fails loudly),
#   - the section 5 vote table (min level / max votes),
#   - the preferred-anchor-kind table.
# If DESIGN.md's table shape drifts (missing row, renamed header, moved section) the script
# goes red with a named failure, never quietly green. Prints one line per enemy plus a final
# "12/12" verdict; exit 0 only when every enemy passes every field.

const ENEMY_DIR := "game/content/enemies"
const EXPECTED_ROSTER := 12

var _design_lines: PackedStringArray = []
var _global_failures: Array[String] = []


func _init() -> void:
	var root := _repo_root()
	if root == "":
		_global_failures.append("DESIGN.md or game/content/enemies not found walking up from %s" % _cwd())
		_report_and_quit({}, {})
		return
	var df := FileAccess.open(root.path_join("DESIGN.md"), FileAccess.READ)
	if df == null:
		_global_failures.append("cannot read %s" % root.path_join("DESIGN.md"))
		_report_and_quit({}, {})
		return
	_design_lines = df.get_as_text().split("\n")
	df.close()

	# The roster comes from the filesystem; names come from the JSON files themselves.
	var enemy_root := root.path_join(ENEMY_DIR)
	var dir := DirAccess.open(enemy_root)
	if dir == null:
		_global_failures.append("cannot open %s" % enemy_root)
		_report_and_quit({}, {})
		return
	var ids: Array[String] = []
	var docs: Dictionary = {}
	var name_to_id: Dictionary = {}
	for sub in dir.get_directories():
		if sub.begins_with("."):
			continue
		var epath := enemy_root.path_join(sub).path_join("enemy.json")
		if not FileAccess.file_exists(epath):
			continue
		var ef := FileAccess.open(epath, FileAccess.READ)
		if ef == null:
			_global_failures.append("%s: unreadable" % epath)
			continue
		var parsed: Variant = JSON.parse_string(ef.get_as_text())
		ef.close()
		if not (parsed is Dictionary):
			_global_failures.append("%s: does not parse as a Dictionary" % epath)
			continue
		ids.append(sub)
		docs[sub] = parsed
		name_to_id[_norm_name(str((parsed as Dictionary).get("name", "")))] = sub
	ids.sort()
	if ids.size() != EXPECTED_ROSTER:
		_global_failures.append("expected %d enemy folders with enemy.json, found %d" % [EXPECTED_ROSTER, ids.size()])

	# Parse the DESIGN.md tables once; any shape drift lands here, loudly.
	var sr2 := _find_table(["| enemy", "height (u)", "diameter (u)"])
	var sr5 := _find_table(["| body", "base speed (u/s)", "ceiling"])
	var vote := _find_table(["| #", "min level", "max votes"])
	var anchors := _find_table(["| enemy", "preferred kind"])
	var burst_bound := _burst_bound()
	if sr2.is_empty():
		_global_failures.append("SR-2 body-size table not found in DESIGN.md (header '| enemy | height (u) | diameter (u) |')")
	if sr5.is_empty():
		_global_failures.append("SR-5 pursuit-ceiling table not found in DESIGN.md (header '| body | base speed (u/s) | ceiling |')")
	if vote.is_empty():
		_global_failures.append("vote table not found in DESIGN.md (header '| # | ... min level | max votes ...')")
	if anchors.is_empty():
		_global_failures.append("preferred-anchor-kind table not found in DESIGN.md (header '| enemy | preferred kind |')")
	if burst_bound < 0.0:
		_global_failures.append("SR-5 burst-bound sentence ('may reach <n> x base run speed') not found in DESIGN.md")
	if not _global_failures.is_empty():
		_report_and_quit(docs, name_to_id, ids)
		return

	var results: Dictionary = {}
	print("T-073 enemy data check (DESIGN.md section 5 read at run time)")
	for id in ids:
		results[id] = _check_enemy(id, docs[id], name_to_id, sr2, sr5, vote, anchors, burst_bound)
	_report_and_quit(docs, name_to_id, ids, results)


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


func _norm_name(s: String) -> String:
	# Lowercase, strip parentheticals, keep [a-z0-9], collapse the rest to single spaces.
	var t := s.to_lower()
	var out := ""
	var depth := 0
	for i in range(t.length()):
		var ch := t[i]
		if ch == "(":
			depth += 1
			continue
		if ch == ")":
			depth = maxi(depth - 1, 0)
			continue
		if depth > 0:
			continue
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		else:
			out += " "
	return " ".join(out.split(" ", false))


func _cells(line: String) -> Array:
	var t := line.strip_edges()
	if t.begins_with("|"):
		t = t.substr(1)
	if t.ends_with("|"):
		t = t.substr(0, t.length() - 1)
	var out: Array = []
	for c in t.split("|"):
		out.append(c.strip_edges())
	return out


func _is_separator(cells: Array) -> bool:
	for c in cells:
		var s := str(c).replace("-", "").replace(":", "").replace(" ", "")
		if s != "":
			return false
	return true


# Find a markdown table by header-line substrings; return its data rows as cell arrays.
# Empty result = table shape drifted (reported loudly by the caller).
func _find_table(must_contain: Array) -> Array:
	for i in range(_design_lines.size()):
		var line: String = _design_lines[i]
		if not line.strip_edges().begins_with("|"):
			continue
		var ok := true
		for s in must_contain:
			if not line.contains(str(s)):
				ok = false
				break
		if not ok:
			continue
		var rows: Array = []
		var j := i + 1
		while j < _design_lines.size() and _design_lines[j].strip_edges().begins_with("|"):
			var cells := _cells(_design_lines[j])
			if not _is_separator(cells):
				rows.append(cells)
			j += 1
		return rows
	return []


func _floats(s: String) -> Array:
	var re := RegEx.new()
	re.compile("[0-9]+(\\.[0-9]+)?")
	var out: Array = []
	for m in re.search_all(s):
		out.append(float(m.get_string()))
	return out


func _row_for(rows: Array, enemy_name: String, name_index: int = 0) -> Array:
	var want := _norm_name(enemy_name)
	for cells in rows:
		if cells.size() > name_index and _norm_name(str(cells[name_index])) == want:
			return cells
	return []


# SR-5 prose: "a telegraphed sprint (Zoomies) may reach 1.00 x base run speed".
# The bound itself is parsed from the sentence - its absence fails loudly.
func _burst_bound() -> float:
	for line in _design_lines:
		var at := line.find("may reach")
		if at == -1:
			continue
		var f := _floats(line.substr(at))
		if not f.is_empty():
			return float(f[0])
	return -1.0


func _stats(doc: Dictionary) -> Dictionary:
	var s: Variant = doc.get("stats", {})
	return s if s is Dictionary else {}


func _check_enemy(id: String, doc: Dictionary, name_to_id: Dictionary, sr2: Array, sr5: Array,
		vote: Array, anchors: Array, burst_bound: float) -> Array:
	var fails: Array[String] = []
	var notes: Array[String] = []
	var st := _stats(doc)
	var enemy_name := str(doc.get("name", ""))
	if enemy_name == "":
		fails.append("name is missing")
	if _norm_name(enemy_name) != _norm_name(id) and not name_to_id.has(_norm_name(enemy_name)):
		fails.append("name '%s' does not normalize to any folder name" % enemy_name)
	if str(doc.get("id", "")) != id:
		fails.append("id '%s' != folder '%s'" % str(doc.get("id", "")))

	# ---- SR-2 body size: height + hit diameter -------------------------------
	var row := _row_for(sr2, enemy_name)
	if row.is_empty():
		if id == "nuke" or id == "gift_larper":
			notes.append("no SR-2 row (section 5 carries no world size for this row)")
			if id == "nuke":
				if absf(float(st.get("world_height", -1.0))) > 1e-9:
					fails.append("nuke has no body but stats.world_height == %s" % str(st.get("world_height")))
				_check_no_hit_diameter(fails, st)
		else:
			fails.append("no SR-2 row for '%s' in DESIGN.md" % enemy_name)
	else:
		var height_cell := str(row[1])
		var diameter_cell := str(row[2]) if row.size() > 2 else ""
		if height_cell.contains("squashed"):
			var hf := _floats(height_cell)  # [squashed, extended]
			if hf.size() < 2:
				fails.append("SR-2 coil height cell '%s' did not parse" % height_cell)
			else:
				_approx(fails, "squashed height", st.get("squashed_height_u", null), hf[0])
				_approx(fails, "extended height", st.get("extended_height_u", null), hf[1])
		else:
			var hf := _floats(height_cell)
			if hf.is_empty():
				fails.append("SR-2 height cell '%s' did not parse" % height_cell)
			else:
				_approx(fails, "world_height", st.get("world_height", null), hf[0])
				if st.has("body_height"):
					_approx(fails, "body_height", st.get("body_height"), hf[0])
		var dflt := _floats(diameter_cell)
		if dflt.is_empty():  # em dash: no body contact, no diameter stated
			_check_no_hit_diameter(fails, st)
		else:
			var got = st.get("hit_diameter", st.get("hit_diameter_u", null))
			if got == null:
				fails.append("hit_diameter missing (SR-2 says %.3f u)" % float(dflt[0]))
			else:
				_approx(fails, "hit_diameter", got, dflt[0])

	# ---- SR-5 pursuit ceiling (floating bodies only) --------------------------
	var prow := _row_for(sr5, enemy_name)
	if prow.is_empty():
		notes.append("not a floating body; pursuit_ceiling marker 0.0 expected")
		if not st.has("pursuit_ceiling"):
			fails.append("pursuit_ceiling missing (non-floater marker 0.0 expected, D-T073-1)")
		elif absf(float(st.get("pursuit_ceiling"))) > 1e-9:
			fails.append("pursuit_ceiling == %s but '%s' is not a floating body in SR-5 (marker 0.0 expected)" % [str(st.get("pursuit_ceiling")), enemy_name])
	else:
		var pf := _floats(str(prow[2]))
		_approx(fails, "pursuit_ceiling", st.get("pursuit_ceiling", null), pf[0] if not pf.is_empty() else -1.0)
		var bf := _floats(str(prow[1]))
		if not bf.is_empty() and st.has("base_speed"):
			_approx(fails, "base_speed", st.get("base_speed"), bf[0])

	# ---- burst ceiling: present, inside the SR-5 prose bound ------------------
	if not st.has("burst_ceiling"):
		fails.append("burst_ceiling missing")
	else:
		var bc := float(st.get("burst_ceiling"))
		if bc < 0.0 or bc > burst_bound:
			fails.append("burst_ceiling == %s, outside the SR-5 bound [0.0, %.3f]" % [str(bc), burst_bound])

	# ---- vote table: first-shown level + max votes ---------------------------
	var vrow := _row_for(vote, enemy_name, 1)
	if vrow.is_empty():
		fails.append("no row for '%s' in the section 5 vote table" % enemy_name)
	else:
		if int(doc.get("min_level", -1)) != int(float(str(vrow[2]))):
			fails.append("min_level == %s, vote table says %s" % [str(doc.get("min_level")), str(vrow[2])])
		if int(doc.get("max_votes", -1)) != int(float(str(vrow[3]))):
			fails.append("max_votes == %s, vote table says %s" % [str(doc.get("max_votes")), str(vrow[3])])

	# ---- preferred anchor kind -------------------------------------------------
	var arow := _row_for(anchors, enemy_name)
	if arow.is_empty():
		fails.append("no row for '%s' in the preferred-anchor-kind table" % enemy_name)
	else:
		var kind := str(arow[1]).replace("`", "").strip_edges().to_lower()
		var top := str(doc.get("preferred_kind", ""))
		var nested := str(st.get("preferred_kind", ""))
		if top == "" and nested == "":
			fails.append("preferred_kind missing (table says '%s')" % kind)
		else:
			if top != "" and top != kind:
				fails.append("preferred_kind == '%s', table says '%s'" % [top, kind])
			if nested != "" and top != "" and nested != top:
				fails.append("preferred_kind drift: top-level '%s' vs stats '%s'" % [top, nested])

	# ---- counter-play line + tell line (non-empty, top level) -----------------
	if str(doc.get("counter_play", "")).strip_edges() == "":
		fails.append("counter_play missing or empty (top-level altar-panel line)")
	if str(doc.get("tell", "")).strip_edges() == "":
		fails.append("tell missing or empty (top-level altar-panel line)")

	if fails.is_empty():
		notes.append("all fields match")
	if fails.is_empty():
		print("  PASS %s - %s" % [id, "; ".join(notes)])
	else:
		print("  FAIL %s - %s" % [id, "; ".join(fails)])
	return fails


func _check_no_hit_diameter(fails: Array[String], st: Dictionary) -> void:
	var got = st.get("hit_diameter", st.get("hit_diameter_u", null))
	if got != null and absf(float(got)) > 1e-9:
		fails.append("hit_diameter == %s but DESIGN.md states no hit diameter for this row" % str(got))


func _approx(fails: Array[String], what: String, got, want) -> void:
	if got == null:
		fails.append("%s missing (DESIGN.md says %.4f)" % [what, float(want)])
		return
	if absf(float(got) - float(want)) > 1e-6:
		fails.append("%s == %s, DESIGN.md says %.4f" % [what, str(got), float(want)])


func _report_and_quit(_docs: Dictionary, _name_to_id: Dictionary, ids: Array = [], results: Dictionary = {}) -> void:
	var failed := 0
	for f in _global_failures:
		print("  FAIL global - %s" % f)
		failed += 1
	var passed := 0
	for id in ids:
		if results.has(id):
			if (results[id] as Array).is_empty():
				passed += 1
			else:
				failed += 1
		else:
			print("  FAIL %s - not checked (see global failures)" % id)
			failed += 1
	var total := maxi(ids.size(), EXPECTED_ROSTER)
	print("T-073 enemy data check: %d/%d enemies match DESIGN.md section 5" % [passed, EXPECTED_ROSTER])
	if failed > 0 or passed != EXPECTED_ROSTER or total != EXPECTED_ROSTER:
		print("T-073 RESULT: FAIL (%d failure group(s))" % failed)
		quit(1)
		return
	print("T-073 RESULT: OK")
	quit(0)

