extends RefCounted
#
# early_bird.gd — the Early Bird script curse (DESIGN.md section 7.2, GENERAL family;
# ticket T-051).
#
# Rule: "enemies spawn 2 s after level start instead of 6 s".
#
# The enemy runtime already carries the level-start spawn delay as one field with the
# Early Bird value named in its comment (sim/enemy_runtime.gd: SPAWN_DELAY_TICKS 360,
# "Early Bird: the caller passes 120"). on_level_start writes exactly that value into
# the run's EnemyRuntime through the state surface (D-T051-1's "enemy_runtime" key);
# it never re-derives the base delay, so the base stays whatever the runtime says.
#
# 2 s = 120 whole 60 Hz ticks, level >= 2 gate is the JSON's min_level (T-050's draw
# logic) — this module is only the timing payload.

const CURSE_ID := "early_bird"
const SPAWN_DELAY_TICKS := 120  # 2.0 s at 60 Hz (DESIGN.md section 7.2), was 360 (6.0 s)


## Stacks the run holds; >= 1 while the curse is picked (the sim's {curse_id: stacks}).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## on_level_start(state, api): point the run's EnemyRuntime at the early delay.
## Not held: the runtime keeps its own default (6.0 s, three times as long).
static func on_level_start(state: Dictionary, _api) -> void:
	if held_stacks(state) <= 0:
		return
	var rt = state.get("enemy_runtime", null)
	if rt != null:
		rt.spawn_delay_ticks = SPAWN_DELAY_TICKS

