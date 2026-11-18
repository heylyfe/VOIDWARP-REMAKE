extends RefCounted
# Cold Blood (T-053; cold_blood.json, DESIGN.md section 8).
# "overtime tiers rise every 30 s instead of 20 s (Long Night: 21 s instead of 14 s)"
# overtime_period is a closed stat with DEFAULT 20.0 (core/stats.gd) and it is read by
# sim/economy.gd create(), so the effect is a modifier and this file holds no handler.
# The declaration is a mul (20 x 1.5 = 30 s), not a set: the row's own parenthetical is
# multiplicative (14 x 1.5 = 21 s under Long Night), and `set` wins over every other
# modifier on a stat, which would flatten the curse instead of composing with it.
# Long Night still ships `set 14`, which wins over this mul, so the pair reads 14 s until
# that curse is declared mul 0.7 - content/curses/long_night.json, not this file.

const UPGRADE_ID := "cold_blood"
const PERIOD_MUL := 1.5
