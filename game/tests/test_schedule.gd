extends RefCounted
#
# test_schedule.gd (ticket T-023): the one tunable file drives the lobby.
#   - levels 0..40 of data/offering_schedule.json produce the bays of DESIGN.md
#     section 6, including the 25-30 repeat block (31..36 == 25..30, forever);
#   - a full walk of levels 0..40 (resolving every mandatory bay) reproduces the
#     "enemies in play next level" column - VOTING RULES canon: votes accumulate;
#   - the data-edit proof: changing ONE entry in the JSON changes the lobby with
#     no code edit (the test edits the file, reloads the content api, observes the
#     change, and restores the original bytes).

const ContentApiScript := preload("res://core/content_api.gd")
const Intermission := preload("res://sim/intermission.gd")

## DESIGN.md section 6, compactly: level -> [bay, E vote count when != 1, REST discount].
## Row = the lobby AFTER completing that level (0 = pre-run).
const WANT := {
	0: [["CLASS"], ["E", 1, "starter"]],
	1: [["E", 1, "starter"], ["U"]],
	2: [["C"]],
	3: [["E", 1]],
	4: [["C"], ["U"]],
	5: [["REST", 0, "", 20]],
	6: [["C"], ["E", 1]],
	7: [["E", 1], ["U"]],
	8: [["C"]],
	9: [["E", 1]],
	10: [["C"], ["U"]],
	11: [["REST", 0, "", 20]],
	12: [["C"], ["E", 1]],
	13: [["E", 1], ["U"]],
	14: [["C"]],
	15: [["E", 1]],
	16: [["C"], ["U"]],
	17: [["REST", 0, "", 20]],
	18: [["C"], ["E", 2]],
	19: [["E", 2], ["U"]],
	20: [["C"]],
	21: [["E", 1]],
	22: [["C"], ["U"]],
	23: [["REST", 0, "", 20]],
	24: [["C"], ["E", 2]],
	25: [["E", 2], ["U"]],
	26: [["C"]],
	27: [["E", 2]],
	28: [["C"], ["U"]],
	29: [["REST", 0, "", 20]],
	30: [["C"], ["E", 2]],
}

## "enemies in play next level" (DESIGN.md section 6 table): must equal the accumulated
## votes after resolving every lobby from 0 through p_level.
const IN_PLAY := {
	0: 1, 1: 2, 2: 2, 3: 3, 4: 3, 5: 3, 6: 4, 7: 5, 8: 5, 9: 6,
	10: 6, 11: 6, 12: 7, 13: 8, 14: 8, 15: 9, 16: 9, 17: 9, 18: 11, 19: 13,
	20: 13, 21: 14, 22: 14, 23: 14, 24: 16, 25: 18, 26: 18, 27: 20, 28: 20, 29: 20,
	30: 22,
}

const SCHEDULE_PATH := "res://data/offering_schedule.json"
## The tracked schedule is backed up here before the data-edit block touches it, and the
## restore copies it back from this backup rather than from memory - a crash between the
## rewrite and the restore leaves this copy to recover from. Deleted on a clean finish.
const BACKUP_PATH := "user://offering_schedule_test_backup.json"


func run() -> Array[String]:
	var f: Array[String] = []
	var api := ContentApiScript.load()
	if not bool(api.is_ok()):
		f.append("content api boot failed: %s" % " / ".join(api.boot_errors()))
		return f
	_rows(f, api)
	_repeat_block(f, api)
	_walk(f, api)
	_data_edit_changes_the_lobby(f, api)
	return f


## Compare Intermission.bays_for_level against WANT, levels 0..40.
func _rows(f: Array[String], api: RefCounted) -> void:
	for level in range(41):
		if not WANT.has(level):
			continue
		var got: Array = Intermission.bays_for_level(api, level)
		var want: Array = WANT[level]
		if got.size() != want.size():
			f.append("level %d: %d bays, want %d (%s)" % [level, got.size(), want.size(), _brief(got)])
			continue
		for i in want.size():
			var w: Array = want[i]
			var g: Dictionary = got[i]
			var kind := str(w[0])
			if str(g.get("bay", "")) != kind:
				f.append("level %d bay %d: got %s, want %s" % [level, i, str(g.get("bay")), kind])
				continue
			if kind == "E":
				if int(g.get("count", 1)) != int(w[1]):
					f.append("level %d: E count %d, want %d" % [level, int(g.get("count", 1)), int(w[1])])
				var want_pool := str(w[2]) if w.size() > 2 else ""
				if want_pool != "starter" and str(g.get("pool", "")) == "starter":
					f.append("level %d: E pool is starter, want full" % level)
				if want_pool == "starter" and str(g.get("pool", "")) != "starter":
					f.append("level %d: E pool must be starter" % level)
			if kind == "REST" and want[i].size() > 3:
				if int(g.get("discount_pct", 0)) != int(w[3]):
					f.append("level %d: REST discount %d, want %d" % [level, int(g.get("discount_pct", 0)), int(w[3])])


func _brief(p_bays: Array) -> String:
	var out := ""
	for b in p_bays:
		out += str(b.get("bay"), ",") if out == "" else " " + str(b.get("bay"))
	return out


## 31..36 == rows 25..30, and 37..40 restart the block (rows 25-30 repeat forever).
func _repeat_block(f: Array[String], api: RefCounted) -> void:
	for i in range(6):
		var a: Array = Intermission.bays_for_level(api, 25 + i)
		var b: Array = Intermission.bays_for_level(api, 31 + i)
		if _brief(a) != _brief(b):
			f.append("repeat: level %d (%s) != level %d (%s)" % [25 + i, _brief(a), 31 + i, _brief(b)])
	for i in range(4):
		var a: Array = Intermission.bays_for_level(api, 25 + i)
		var b: Array = Intermission.bays_for_level(api, 37 + i)
		if _brief(a) != _brief(b):
			f.append("repeat: level %d != level %d (second lap)" % [25 + i, 37 + i])
	# and the E counts survive the copy
	for level in [31, 33, 37]:
		var bays: Array = Intermission.bays_for_level(api, level)
		for b in bays:
			if str(b.get("bay")) == "E" and int(b.get("count", 1)) != 2:
				f.append("repeat: level %d E count %d, want 2" % [level, int(b.get("count", 1))])


## A full walk: lobbies 0..40 in sequence, every mandatory bay resolved through the
## Select path; the accumulated votes must match the "enemies in play" column.
func _walk(f: Array[String], api: RefCounted) -> void:
	var votes: Dictionary = {}
	var curses: Dictionary = {}
	var stacks: Dictionary = {}
	var purse := 0
	var tithes := 0
	for level in range(41):
		var lb: RefCounted = Intermission.create(api, level, purse, 7000 + level,
				votes, curses, stacks, "dasher", tithes)
		if not lb.gate_open():
			_resolve_all(lb, f, level)
		votes = lb.votes
		curses = lb.curses_held
		stacks = lb.upgrade_stacks
		purse = int(lb.purse)
		tithes = int(lb.tithes)
		if not lb.gate_open():
			f.append("level %d: gate did not open after resolving the bays" % level)
			return
		if IN_PLAY.has(level) and lb.votes_sum() != int(IN_PLAY[level]):
			f.append("level %d: %d enemies in play after the lobby, want %d"
					% [level, lb.votes_sum(), int(IN_PLAY[level])])


## Resolves every mandatory bay of one lobby (select altar 0 of each; a C bay picks
## the first curse or pays the tithe when its draw is somehow empty).
func _resolve_all(lb: RefCounted, f: Array[String], level: int) -> void:
	for _round in range(4):
		var table: Array = lb.altar_table()
		var done := true
		for entry in table:
			var bi := int(entry["bay_index"])
			var bay: Dictionary = lb.bays[bi]
			var kind := str(bay["kind"])
			if str(entry["kind"]) == "offer" and (kind == "E" or kind == "CLASS"):
				if not bool(bay["resolved"]):
					lb.apply_select(0, _offset(table, entry), f)
					done = false
			elif str(entry["kind"]) == "offer" and kind == "C" and not bool(bay["resolved"]):
				lb.apply_select(0, _offset(table, entry), f)
				done = false
			elif str(entry["kind"]) == "tithe" and kind == "C" and not bool(bay["resolved"]):
				# a C bay with an empty draw can only be tithe-passed
				if (bay["altars"] as Array).is_empty() and lb.purse >= int(bay.get("tithe", 0)):
					lb.apply_select(0, _table_index(table, entry, "tithe"), f)
					done = false
		if done:
			return
	f.append("level %d: mandatory bays never resolved" % level)


## Flat-table index of a (bay_index, altar) offer pair.
func _offset(p_table: Array, p_entry: Dictionary) -> int:
	for i in p_table.size():
		if int(p_table[i]["bay_index"]) == int(p_entry["bay_index"]) \
				and int(p_table[i]["altar"]) == int(p_entry["altar"]) \
				and str(p_table[i]["kind"]) == "offer":
			return i
	return -1


func _table_index(p_table: Array, p_entry: Dictionary, p_kind: String) -> int:
	for i in p_table.size():
		if int(p_table[i]["bay_index"]) == int(p_entry["bay_index"]) \
				and str(p_table[i]["kind"]) == p_kind:
			return i
	return -1


## THE done-when: one JSON entry changes the lobby with no code edit.
## Edits level 3's single vote into an E x2 (count 2), reloads, observes the change,
## and restores the original bytes from the user:// backup.
func _data_edit_changes_the_lobby(f: Array[String], api: RefCounted) -> void:
	var original := FileAccess.get_file_as_string(SCHEDULE_PATH)
	if original.strip_edges().is_empty():
		f.append("data-edit: could not read %s" % SCHEDULE_PATH)
		return
	# Back the tracked file up under user:// BEFORE the rewrite, so a crash between the
	# write and the restore leaves the only full copy of the original recoverable. If the
	# backup cannot be written, the tracked file is left untouched.
	var bak := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
	if bak == null:
		f.append("data-edit: could not back the schedule up under user://")
		return
	bak.store_string(original)
	bak.close()
	var doc: Dictionary = JSON.parse_string(original)
	var lvl3: Array = doc["levels"]["3"]
	lvl3[0]["count"] = 2
	var ok := _write_json(doc)
	if not ok:
		f.append("data-edit: could not rewrite the schedule file")
		_restore_from_backup()
		_rm_backup()
		return
	var api2 := ContentApiScript.load()
	# The file is dirty only across the write and this one reload: restore it here, before
	# any assertion can fail, and let every check below read api2 (the parsed copy). GDScript
	# has no finally, so a no-op guard around a later restore would promise nothing.
	_restore_from_backup()
	var changed: Array = Intermission.bays_for_level(api2, 3)
	var single: Array = Intermission.bays_for_level(api, 3)   # the OLD api is untouched
	if single.size() != 1 or int(single[0].get("count", 1)) != 1:
		f.append("data-edit: the pre-edit api must still see count 1 (saw %s)" % _brief(single))
	if changed.size() != 1 or int(changed[0].get("count", 1)) != 2:
		f.append("data-edit: level 3 still %s after the JSON edit - the lobby did not follow the file" % _brief(changed))
	# the edited data drives a real lobby's E count with no code involved
	var lb: RefCounted = Intermission.create(api2, 3, 0, 11)
	var e_found := 0
	for bay in lb.bays:
		if str(bay["kind"]) == "E":
			e_found += 1
			if int(bay.get("count", 1)) != 2:
				f.append("data-edit: lobby E bay count %d, want 2" % int(bay.get("count", 1)))
			# 2 votes are owed and none are cast yet: the gate must still be shut, or the
			# vote-count block below (which only runs while it is shut) proves nothing.
			if lb.gate_open():
				f.append("data-edit: the gate is open before any vote is cast")
	if e_found != 1:
		f.append("data-edit: lobby has %d E bays after the edit" % e_found)
	# two votes must be cast before the gate opens
	if not lb.gate_open():
		var saw_open := false
		for _v in range(3):
			lb.step([_select_first_offers(lb)])
			if lb.gate_open():
				saw_open = true
				break
		if not saw_open:
			f.append("data-edit: level 3 gate never opened after 3 selects")
		# and exactly 2 votes were consumed
		for bay in lb.bays:
			if str(bay["kind"]) == "E" and int(bay.get("cast", 0)) != 2:
				f.append("data-edit: cast %d votes, want 2" % int(bay.get("cast", 0)))
	var api3 := ContentApiScript.load()
	if _brief(Intermission.bays_for_level(api3, 3)) != _brief(Intermission.bays_for_level(api, 3)):
		f.append("data-edit: the restored file does not match the original lobby")
	_rm_backup()


func _write_json(p_doc: Dictionary) -> bool:
	var fa := FileAccess.open(SCHEDULE_PATH, FileAccess.WRITE)
	if fa == null:
		return false
	fa.store_string(JSON.stringify(p_doc, "\t") + "\n")
	fa.close()
	return true


## Copies the user:// backup back over the tracked file (the backup is the copy of record
## for the restore, written before the rewrite above ran). If the backup cannot be read,
## the tracked file is left alone and the backup is kept for manual recovery.
func _restore_from_backup() -> void:
	var bytes := FileAccess.get_file_as_string(BACKUP_PATH)
	if bytes == "":
		return
	var fa := FileAccess.open(SCHEDULE_PATH, FileAccess.WRITE)
	if fa != null:
		fa.store_string(bytes)
		fa.close()


func _rm_backup() -> void:
	if FileAccess.file_exists(BACKUP_PATH):
		DirAccess.remove_absolute(BACKUP_PATH)


##_select_first_offers: selects the first unresolved offer of every bay in one tick.
func _select_first_offers(lb: RefCounted) -> RefCounted:
	var InputScript := preload("res://sim/input.gd")
	var table: Array = lb.altar_table()
	var idx := -1
	for i in table.size():
		if str(table[i]["kind"]) == "offer":
			var bay: Dictionary = lb.bays[int(table[i]["bay_index"])]
			if not bool(bay["resolved"]) and str(bay["kind"]) == "E":
				idx = i
				break
	return InputScript.new(0, 0, 0, idx)
