extends RefCounted
#
# Shared helpers for the T-012 controller tests. Not discovered by run_all.gd (its name
# does not start with test_). Tests preload this file by path.

const ControllerScript := preload("res://sim/controller.gd")
const CollisionScript := preload("res://sim/collision.gd")

const DT := 1.0 / 60.0


static func consts() -> Dictionary:
	return ControllerScript.load_constants()


static func mk_in(mx: int = 0, mz: int = 0, buttons: int = 0, ax: float = 0.0,
		az: float = 1.0) -> Dictionary:
	return {
		"move_x": mx, "move_z": mz, "buttons": buttons,
		"aim_x": ax, "aim_z": az,
	}


# Steps n ticks, collecting all events. input_fn(ctl, tick) -> Dictionary.
static func run_ticks(ctl, w: Dictionary, n: int, input_fn: Callable = Callable(),
		ev_out: Array = []) -> Array:
	for i in range(n):
		var a_in: Dictionary = mk_in()
		if input_fn.is_valid():
			a_in = input_fn.call(ctl, i)
		var ev = ctl.step(DT, a_in, w)
		for e in ev:
			ev_out.append(e)
	return ev_out


# tiles: Array of [x, z, y_hu] flat tiles.
static func world_from_tiles(tiles: Array, pads: Array = []) -> Dictionary:
	var tl: Array = []
	for t in tiles:
		tl.append([t[0], t[1], t[2], 0, 0])
	return CollisionScript.make_world(tl, [], pads)
