extends RefCounted
#
# answers.gd - the shared answer table (ticket T-075, piece 1 of 3).
#
# Source of truth: research/fable-enemies.md section 4 (the counter-play map).
# The answers below are COPIED from that table, not invented; each entry names
# its row under "source". The FLEET_PACK addendum (research/fable-tickets.md
# row T-026) says this one module drives T-075's answer bots AND T-026's
# --dodge flag - so the API is deliberately plain data.
#
# Module contract:
#   DELAY_TICKS - the addendum's reaction delay: the bot plays the first input
#                 15 ticks (60 Hz = 0.25 s) after the event that starts the
#                 answer, never on the event itself (a bot that reacts on the
#                 tick a telegraph appears measures nothing).
#   TABLE       - one entry per enemy id, twelve in all. Keys:
#                   enemy    the id itself
#                   answer   the documented verb phrase (verbatim, section 4)
#                   trigger  the telegraph event that starts the answer
#                   anchor   the sub-event inputs are timed against; null means
#                            the trigger itself. Some answers key off a later
#                            sub-event the bot re-anchors to (e.g. "bark" -
#                            the answer starts on the bark, after the 0.75 s
#                            line telegraph).
#                   inputs   the sequence the bot plays, as
#                            [{tick_offset, action, note}, ...] relative to
#                            (anchor or trigger) + DELAY_TICKS
#                   source   the section 4 row it came from
#                   caveat   optional - when the table itself says the answer
#                            is conditional or unanswerable, the row is
#                            reproduced here. That is a finding, not a failure.
#   A "note" on an input never changes the input; it only carries the section 4
#   arithmetic the re-timing bot needs.
#
# Input vocabulary (closed for piece 1; T-075's bot and T-026's --dodge both
# interpret these):
#   jump              - tap jump; the generic vertical answer (hurdle / jump on
#                       the bark / jump as the ring crosses)
#   move_out          - run straight away from the threat's footpoint or centre
#   move_around       - walk around the threat, never over it
#   move_out_of_patch - step off the marked cells (gin)
#   stop              - stop at once; do nothing
#   step_behind_rise  - get behind a 2 HU rise / a height step or prop
#
# The void dive (F5) is available against everything and is NOT repeated in
# the entries - per the section 4 rule.
#
# KNOWN GAPS (copied from section 4, each also noted on its entry):
#   - claude's answer is a ROUTE (collect clawds), not an input sequence: the bot
#     does not path to clawds, so a bot run that votes Claude dies at 180 s
#     (cycle 7 revamp, D-T4-5).
#   - isagi with Egoist down a flat in-line lane has no answer (F6).
#   - address me is answerable only with F8 (co-arrival with a chaser).

# The T-026 addendum: the answer starts "15 ticks after the event".
const DELAY_TICKS := 15

const TABLE := {
	"address_me": {
		"enemy": "address_me",
		"answer": "stop at once; do nothing for 1.5 s",
		"trigger": "trumpet, then a 5.0 s rumble",
		"anchor": "trumpet",
		"inputs": [
			{"tick_offset": 0, "action": "stop", "note": "1.5 s of zero movement; 3.5 s of slack in total (section 4)"},
		],
		"source": "research/fable-enemies.md section 4 (counter-play map), row 'address me'",
		"caveat": "survivable today only with F8 - otherwise it can arrive with a chaser 3 u away and both kill",
	},
	"claude": {
		"enemy": "claude",
		"answer": "collect clawds: each pickup resets his anger timer to 0, and the timer freezes once the beacon opens",
		"trigger": "a warning chime at 60 s, a louder alarm at 120 s, the insta-kill at 180 s",
		"anchor": "warning",
		"inputs": [
			{"tick_offset": 0, "action": "move_around", "note": "route to the nearest clawd; the pickup radius is the gift radius (1.6 u) and the clawds are spread over the walkable tiles"},
		],
		"source": "research/fable-enemies.md section 4 (counter-play map), row 'Claude' - rewritten for the cycle-7 revamp (D-T4-5): content/enemies/claude/enemy.json, sim/clawds.gd",
		"caveat": "the bot does not route to clawds, so a bot run that votes Claude dies at 180 s; the body still kills on contact",
	},
	"coil": {
		"enemy": "coil",
		"answer": "leave the ring (1.2 u) - and be airborne or > 6 u away when it lands",
		"trigger": "\"boing\" + landing ring at your feet, 0.6 s; arc 2.75 s",
		"anchor": null,
		"inputs": [
			{"tick_offset": 0, "action": "move_out", "note": "3.35 s to move 6 u - trivial unless pinned by something else; needs the push to have a duration (section 2)"},
		],
		"source": "research/fable-enemies.md section 4 (counter-play map), row 'coil'",
	},
	"gift_larper": {
		"enemy": "gift_larper",
		"answer": "look before you grab; walk around it - never over it",
		"trigger": "pink particles and the star inside 12 u; slow rotation",
		"anchor": null,
		"inputs": [
			{"tick_offset": 0, "action": "move_around", "note": "never cross the tile the star sits on; 12 u = 1.3 s of warning at run speed, 0.67 s under Method Acting (D-026)"},
		],
		"source": "research/fable-enemies.md section 4 (counter-play map), row 'gift Larpar'",
	},
	"gin": {
		"enemy": "gin",
		"answer": "walk out of the patch (3 cells)",
		"trigger": "red outline + cracking rumble 2.0 s on a 5x5 patch",
		"anchor": null,
		"inputs": [
			{"tick_offset": 0, "action": "move_out_of_patch", "note": "0.33 s needed of 2.0 s given"},
		],
		"source": "research/fable-enemies.md section 4 (counter-play map), row 'gin ichimaru'",
	},
	"isagi": {
		"enemy": "isagi",
		"answer": "get a 2 HU step between you and him, or jump after the release flash, or sidestep >= 0.9 u where the path allows",
		"trigger": "flash + voice cue 1.2 s",
		"anchor": "release_flash",
		"inputs": [
			{"tick_offset": 0, "action": "jump", "note": "0.43 s window against a 0.30 s burst (3 balls); the 2 HU step and the 0.9 u sidestep are the same row's alternatives"},
		],
		"source": "research/fable-enemies.md section 4 (counter-play map), row 'Isagi'",
		"caveat": "NO answer for Egoist bursts down a flat in-line lane (F6) - no sidestep, and no single jump covers the burst",
	},
	"kiwi_cat": {
		"enemy": "kiwi_cat",
		"answer": "open ground: walk away. Thin path or dead end: hurdle it as it arrives",
		"trigger": "meow within 14 u (it is always visible, always slow)",
		"anchor": "arrival",
		"inputs": [
			{"tick_offset": 0, "action": "jump", "note": "the thin-path / dead-end hurdle: 0.43 s jump window for a 0.14 s overlap (F3); on open ground the answer is simply walking away"},
		],
		"source": "research/fable-enemies.md section 4 (counter-play map), row 'kiwi cat'",
		"caveat": "survivable today only with F1 + F2 (an altitude rule and a body size)",
	},
	"nuke": {
		"enemy": "nuke",
		"answer": "leave the 5 u sphere within 1.5 s; bonus: put a wall, a tower or a bridge between you and the sky",
		"trigger": "ground ring follows you 2.5 s with a rising beep; the ring stops",
		"anchor": "ring_stops",
		"inputs": [
			{"tick_offset": 0, "action": "move_out", "note": "13.5 u of running available, 5 u needed (<= 11 u from the back of a nook)"},
		],
		"source": "research/fable-enemies.md section 4 (counter-play map), row 'nuke'",
	},
	"seal": {
		"enemy": "seal",
		"answer": "jump on the bark, or stand a 2 HU step above/below the line",
		"trigger": "dashed line + mouth-open frame 0.75 s, then a bark",
		"anchor": "bark",
		"inputs": [
			{"tick_offset": 0, "action": "jump", "note": "0.5 s jump window for a 0.07 s crossing (section 5 ruling)"},
		],
		"source": "research/fable-enemies.md section 4 (counter-play map), row 'seal'",
	},
	"thicc_ben": {
		"enemy": "thicc_ben",
		"answer": "be >= 4 u from the smoke when it clears; if he is parked on your path, touch him on purpose and steer the launch",
		"trigger": "smoke at the destination 1.25 s, chime in the last 0.5 s",
		"anchor": null,
		"inputs": [
			{"tick_offset": 0, "action": "move_out", "note": "running in a straight line clears the lock by itself (6.75 u away at arrival); he cannot kill"},
		],
		"source": "research/fable-enemies.md section 4 (counter-play map), row 'thicc ben'",
	},
	"toucher": {
		"enemy": "toucher",
		"answer": "keep off its floor, keep height between you (F1), hurdle it on a path",
		"trigger": "squelch when tiles glitch; glitched floor is visible",
		"anchor": null,
		"inputs": [
			{"tick_offset": 0, "action": "jump", "note": "CLOSEST SEQUENCE: only the hurdle part is an input (1.4 u body, apex 2.25 u - the margin is thin). 'Keep off its floor' and the height standoff are stance / map constraints the micro-levels enforce by routing, not inputs - that is why they are carried in the answer string and caveat instead"},
		],
		"source": "research/fable-enemies.md section 4 (counter-play map), row 'toucher'",
		"caveat": "survivable today only after the section-5 rulings (floor fix, F1 handicap)",
	},
	"you": {
		"enemy": "you",
		"answer": "jump as the ring reaches you; or stand >= 1.5 u above or below its feet",
		"trigger": "rumble 1.5 s; the ring is visible as it expands",
		"anchor": "ring_crosses_player",
		"inputs": [
			{"tick_offset": 0, "action": "jump", "note": "jump 1.0 u height spans 0.10-0.65 s of the jump = 0.56 s window for a 0.16 s crossing; the Echo Ring double-jump (0.25-0.65 s before the first ring, again on landing) is hard but learnable"},
		],
		"source": "research/fable-enemies.md section 4 (counter-play map), row 'YOU?!'",
	},
}


static func ids() -> Array:
	var out: Array = TABLE.keys()
	out.sort()
	return out


static func entry(enemy_id: String) -> Dictionary:
	assert(TABLE.has(enemy_id), "answers.gd: unknown enemy id '%s'" % enemy_id)
	return TABLE.get(enemy_id, {})


static func answer_for(enemy_id: String) -> String:
	return entry(enemy_id).get("answer", "")


static func inputs_for(enemy_id: String) -> Array:
	return entry(enemy_id).get("inputs", [])

