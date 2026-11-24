extends RefCounted
#
# D-U5-1: the icon rows' "xN" stack badge is built ONLY for a cell that shows a stack
# count, and every badge it builds is parented to the cell it belongs to.
#
# The badge used to be constructed for every cell and parented only when stacks > 1, so a
# single-stack cell dropped a styled Label on the floor - created, never parented, never
# freed - once per cell per rebuild. The levels 9-12 app sweep (docs/crashhunt/
# sweep_levels_L9-12.md, finding F1) hit it on the empty-ledger vote path, where the
# replayed lobbies award curses and upgrade stacks, while the full-ledger path leaves both
# rows empty: exactly 4 leaked Labels per level build, 680 CanvasItem RIDs and 1372
# ObjectDB instances at 160 entries, and 0 under --vote-mode all.
#
# TEETH, and why the leak test is a child process: the leaked node is DETACHED, so no tree
# walk can see it (counting labels under the row passes with the bug present), and Godot's
# Performance monitors are refreshed once per frame, which a synchronous run() never
# crosses - measured, five orphan Labels moved OBJECT_NODE_COUNT by 0. The one observer
# that does see a detached node is the engine's own exit report. So
# tests/leak_probe_icon_rows.gd is run as a CHILD Godot process and its --verbose dump is
# read: any "Leaked instance: Label" line is the regression. Proven against the old code:
# the same probe reports 48 leaked Labels (6 cycles x 4 curses + 6 x 4 upgrades, one per
# single-stack cell) and this test fails; against the fix it reports 0 and the test passes.
#
# No global class_name; preload() everywhere (the --headless --script rule).

const IconRowsScript := preload("res://view/hud/icon_rows.gd")

const PROBE := "res://tests/leak_probe_icon_rows.gd"


func run() -> Array[String]:
	var f: Array[String] = []
	_test_no_leaked_labels_in_a_child_process(f)
	_test_stacked_cell_still_shows_its_badge(f)
	return f


## The teeth: build icon rows full of single-stack cells in a child process, free every
## instance, and read the engine's at-exit leak report. One leaked badge per cell is what
## the old code produced.
func _test_no_leaked_labels_in_a_child_process(f: Array[String]) -> void:
	var exe := OS.get_executable_path()
	if exe == "":
		f.append("icon rows: OS.get_executable_path() is empty, cannot run the leak probe")
		return
	var dir := ProjectSettings.globalize_path("res://")
	var args := ["--headless", "--verbose", "--path", dir, "--script", PROBE]
	var out: Array = []
	var code := OS.execute(exe, args, out, true)
	if code != 0:
		f.append("icon rows: the leak probe exited %d" % code)
		return
	# OS.execute hands back CHUNKS, not lines: split every chunk before matching, so the
	# count is a real label count and the example is one clean line.
	var ran := false
	var leaked := 0
	var example := ""
	for item in out:
		for raw in str(item).split("\n"):
			var line := str(raw).strip_edges()
			if line.contains("PROBE built"):
				ran = true
			elif line.begins_with("Leaked instance: Label"):
				leaked += 1
				if example == "":
					example = line
	if not ran:
		f.append("icon rows: the leak probe printed no receipt; it did not reach its build pass")
		return
	if leaked > 0:
		f.append("icon rows: %d Label(s) leaked at exit in the probe (%s) - a stack badge is built for a cell that shows no stack count and never parented, so nothing frees it"
			% [leaked, example])


## The behaviour half of the contract: a cell that DOES show a count still gets its badge,
## the single-stack cell beside it gets none, and a rebuild does not accumulate badges.
func _test_stacked_cell_still_shows_its_badge(f: Array[String]) -> void:
	var rows = IconRowsScript.new()
	rows.set_curses([{"id": "no_refunds", "stacks": 3}, {"id": "aftershock", "stacks": 1}])
	var row: Node = rows.get_node_or_null("Rows/CursesRow")
	if row == null:
		f.append("icon rows: no Rows/CursesRow node")
		rows.free()
		return
	if row.get_child_count() != 2:
		f.append("icon rows: %d cells for 2 curses (want 2)" % row.get_child_count())
		rows.free()
		return
	var badges := 0
	var texts: Array[String] = []
	for cell in row.get_children():
		for child in cell.get_children():
			if child is Label:
				badges += 1
				texts.append(str(child.text))
	if badges != 1 or texts[0] != "x3":
		f.append("icon rows: %d stack badge(s) %s on 2 cells (1 stacked x3, 1 single); want exactly one reading 'x3'"
			% [badges, str(texts)])
		rows.free()
		return
	rows.set_curses([{"id": "no_refunds", "stacks": 3}])
	var again := 0
	var row2: Node = rows.get_node_or_null("Rows/CursesRow")
	if row2 != null:
		for cell in row2.get_children():
			for child in cell.get_children():
				if child is Label:
					again += 1
	if again != 1:
		f.append("icon rows: %d badge(s) after a rebuild of one stacked cell (want 1)" % again)
	rows.free()