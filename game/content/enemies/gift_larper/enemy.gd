extends RefCounted
#
# gift Larper behavior module (ticket T-036; logic is T-021's). Lives under content/ so the sim
# core stays enemy-agnostic; it carries NO sim state - it translates the roster numbers
# (DESIGN.md section 5.7 / section 3.3) for the loader.
#
# The tripmine IS the hazard on gift slots: it does not MOVE (no anchor kind, no wander step, no
# attack phase). Its contact rule is the section 3.3 ladder, owned by sim/mines.gd (T-021):
#   the player's CENTRE within CONTACT_RADIUS (0.9 u) HORIZONTAL of the box point, at ANY height
#   - jumping over a mine does NOT avoid contact - then, in the fixed order (D-058):
#   defuse roll -> Subspacial Barrier -> Last Light (D-057) -> death, D-MINE.
# So this row REFUSES the runtime's plain body-contact kill (cfg contact_kill = false,
# D-T-036-3): the ladder is the only kill path and it is not bypassed. There is no per-tick AI on
# purpose; GiftLarperBehavior holds the row still and keeps the drop-in shape (on_spawn/tick).
#
# Each vote adds +3 flat extra mines (TERRAIN_SPEC section 6.8 rolls them into the level's slot
# set; the 20% hard cap still applies - never more than the cap, never a per-slot-chance change).
#
# Roster numbers (DESIGN.md section 5.7 / section 3.3; the sim constants match):
#   stationary - base_speed 0.0 (PURSUIT/BURST ceilings 0.0, D-T-036-2 [CONTESTABLE]);
#   body 1.0 u tall, hit diameter 0.8 u (D-T-036-1 [CONTESTABLE] - SR-2 gives it no row);
#   first shown at level 5 (section 3.3 CANON: 0 below level 5; 1/20 at 5 -> 1/10 at 25);
#   5-frame rotation cycle, 1 revolution per 4.0 s (48 ticks/frame, 240 ticks/rev - T-083 anim);
#   detonation 18 TOTAL ticks, defused 24 TOTAL ticks (T-083 anim states);
#   tell: pink particles (#FF4FD8) inside 12.0 u; rim glow like a black gift beyond (TBD PNG
#   reads as a black gift there); the star + particles are the tell inside the ramp.

const RT := preload("res://sim/enemy_runtime.gd")

## Roster numbers (DESIGN.md section 5.7 / 3.3; the runtime constants match).
const BODY_HEIGHT := 1.0            # SPEC GAP, D-T-036-1 [CONTESTABLE]; the occupancy-height lift
const HIT_DIAMETER := 0.8          # HITBOXES: 0.8 x body width (the 80 px TBD body at 1.0 u tall)
const BASE_SPEED := 0.0            # stationary slot hazard (D-T-036-2 [CONTESTABLE])
const PURSUIT_CEILING := 0.0       # no pursuit exists to clamp (D-T-036-2)
const BURST_CEILING := 0.0         # no burst exists to bound (D-T-036-2)
const CLIMB := 2.0                 # SR-1 vertical easing cap; never multiplied, never used (no move)
const CONTACT_RADIUS := 0.9        # section 3.3 CANON: horizontal trigger, ANY height (D-058)
const TELL_DISTANCE := 12.0        # section 3.3: inside 12 u the particles + star show
const BLAST_RADIUS := 3.0          # section 3.3: the killing blast on detonation
const FRAMES := 5                  # ENEMIES.md: 5 PNGs cycling (the turning tripmine)
const FRAME_TICKS := 48            # T-083 anim block: 48 ticks per frame
const ROTATION_TICKS := 240        # 5 x 48 = 1 revolution / 4.0 s (section 3.3 CANON)
const ROTATION_PERIOD := 4.0       # seconds
const PARTICLES_PER_SECOND := 12   # T-083 anim block: constant particle emitter
const PARTICLE_COLOR := "#FF4FD8"  # section 3.3: the tell's constant pink
const DETONATION_TICKS := 18       # T-083 anim attack_detonation: 18 TOTAL ticks
const DEFUSED_TICKS := 24          # T-083 anim defused: 24 TOTAL ticks (not per frame)
const DEFUSE_DROP_U := 0.5         # T-083 anim defused: greys out, drops 0.5 u, fades
const MIN_LEVEL := 5               # section 3.3 CANON: no tripmines below level 5
const MAX_VOTES := 5
const MINES_PER_VOTE := 3          # each vote = +3 flat mines
const DEATH_CODE := "D-MINE"       # DESIGN.md section 3.1 / 3.3 (FINAL)
const PREFERRED_KIND := ""         # none: it lives in gift slots (section 5 preferred-kind table)
const DEATH_KILLER := "gift Larper (Tripmine)"   # death.gd's D-MINE display killer


## The runtime cfg this enemy hands to EnemyRuntime.plan()/spawn_at(): everything the
## framework needs to place, size and (not) kill-check the body. Mirror of enemy.json's stats
## block - the test asserts the two agree. contact_kill is FALSE (D-T-036-3): sim/mines.gd's
## ladder owns the kill; the runtime's plain body-contact path never fires for this row.
static func cfg() -> Dictionary:
	return {
		"base_speed": BASE_SPEED,
		"pursuit_ceiling": PURSUIT_CEILING,
		"burst_ceiling": BURST_CEILING,
		"climb_u_per_s": CLIMB,
		"world_height": BODY_HEIGHT,
		"body_height": BODY_HEIGHT,
		"hit_diameter": HIT_DIAMETER,
		"preferred_kind": PREFERRED_KIND,
		"rotation_ticks": ROTATION_TICKS,
		"frame_ticks": FRAME_TICKS,
		"frames": FRAMES,
		"contact_radius": CONTACT_RADIUS,
		"tell_distance": TELL_DISTANCE,
		"blast_radius": BLAST_RADIUS,
		"particles_per_second": PARTICLES_PER_SECOND,
		"particle_color": PARTICLE_COLOR,
		"detonation_ticks": DETONATION_TICKS,
		"defused_ticks": DEFUSED_TICKS,
		"defuse_drop_u": DEFUSE_DROP_U,
		"contact_kill": false,
		"death_code": DEATH_CODE,
		"cycle_s": ROTATION_PERIOD,
		"cycle_ticks": ROTATION_TICKS,
		"frame_w": 256,
		"frame_h": 256,
		"body_rect": [144, 144, 224, 224],   # the T-016 TBD sheet's tight body bbox
	}


## The extra_mines value this roster contributes for `votes` votes (clamped to
## the roster's max): extra_mines += 3 per vote, no cap of its own - the
## terrain's cap math (TERRAIN_SPEC section 6.8) bounds the final count.
static func extra_mines(votes: int) -> int:
	if votes <= 0:
		return 0
	return mini(votes, MAX_VOTES) * MINES_PER_VOTE


## The behavior. Stationary on purpose: no movement, no targeting, no cooldown. The slot
## hazard holds position; the tell (distance read), the detonation (18-tick burst) and the
## defused puff (24-tick grey-out) are VIEW-layer effects keyed off the sim events / tick
## counter - this class only holds the row still and keeps the drop-in contract.
class GiftLarperBehavior:
	extends RT.EnemyBehavior

	func on_spawn(row: Dictionary, _api) -> void:
		row["stationary"] = true

	func tick(_row: Dictionary, _api, _dt_ticks: int) -> void:
		# a tripmine does not think; the mines.gd ladder resolves contact
		pass
