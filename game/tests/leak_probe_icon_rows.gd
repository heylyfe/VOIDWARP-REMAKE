extends SceneTree
#
# D-U5-1 leak probe. NOT a test itself (no test_ prefix, so run_all.gd does not discover
# it): test_hud_icon_badges.gd runs it as a CHILD process so the engine's own at-exit leak
# report can be read as evidence.
#
# Why a child: the leaked node in D-U5-1 is DETACHED - created, never parented, never
# freed - so it is invisible to any tree walk, and Godot's Performance monitors are only
# refreshed once per frame, which a synchronous test never crosses (measured: five orphan
# Labels moved OBJECT_NODE_COUNT by 0). The one thing that does see a detached node is the
# engine's exit report, and that only exists at process exit.
#
# This process builds icon rows the way the empty-ledger level path does - curses and
# upgrade stacks voted in, every cell on a single stack - frees every instance, and quits.
# A leaked stack badge is then reported as "Leaked instance: Label:" in the --verbose dump.
#
# No global class_name; preload() everywhere (the --headless --script rule).

const IconRowsScript := preload("res://view/hud/icon_rows.gd")

const CYCLES := 6
const IDS := ["no_refunds", "aftershock", "brittle", "bunker_buster"]

var _ran := false


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	var items: Array = []
	for id in IDS:
		items.append({"id": str(id), "stacks": 1})
	for _c in CYCLES:
		var rows = IconRowsScript.new()
		rows.set_curses(items)
		rows.set_upgrades(items)
		rows.free()
	# One stacked cell too, so the probe covers the path that DOES parent a badge: a badge
	# that is parented correctly is freed with its cell and must never be reported.
	var stacked = IconRowsScript.new()
	stacked.set_curses([{"id": "no_refunds", "stacks": 3}])
	stacked.free()
	print("PROBE built %d single-stack rows and 1 stacked row, all freed" % CYCLES)
	quit(0)
	return true