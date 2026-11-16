# FABLE_HANDOFF.md — end of the design lead's window

Written 2026-11-16 by the design lead (Fable 5.2). Read after `DECISIONS.md` (its Handover log is the
live state of the specs; this file covers only the last pass).

## Repository state

- Last commit: `14be164` "Pre-fleet checkpoint" — generator version 3, all rulings through D-063
  FINAL, 8 preflight blockers resolved. Gate at that commit, re-run by the lead: harness 5,000 seeds
  32/32 checks pass, gallery 16/16, Godot parity 56/56, validator tests OK.
- **Uncommitted, on purpose (the owner said no commits for this pass):** three new files —
  `research/fable-enemies.md`, `research/fable-funrisks.md`, `research/FABLE_HANDOFF.md`.
- **Nothing else was changed in this pass.** DESIGN.md, FLEET_PACK.md, TERRAIN_SPEC.md, DECISIONS.md,
  ENEMIES.md and all code are exactly as committed. The enemy pass is recommendations and tickets; no
  recommendation has been applied, and no D-entry was written for any of it.

## Completed

| artifact | state |
|---|---|
| Task 2 — `research/fable-enemies.md` | **complete, all seven sections** (0 systemic findings, 1 pressure profiles, 2 terrain pairing, 3 vote economy, 4 counter-play map, 5 rulings on preflight items 8/17/18, 6 tickets + parked items) |
| Task 3 — `research/fable-funrisks.md` | **complete**: 10 risks, each with an earliest signal and a ticket-level mitigation, plus one enabling ticket (T-080) |
| This handoff | complete |

## Cut short mid-section

Nothing was cut mid-section. What is thinner than I would like, honestly stated:
- **No measurement was run for this pass.** Sections 2–5 of the enemy document reuse the preflight
  measurements (anchor availability, props, route times — taken on generator version 2; the shape is
  unchanged in version 3 but the numbers were not re-taken). Every timing window is arithmetic from
  the specified constants, not a simulation.
- **The body-size table (F2) and the first-shown levels are proposals with reasoning, not derived
  values.** They are the least defensible numbers in the document.
- **Line-of-sight availability for the nuke was not measured** (parked item P2 asks the harness to).
- **Stack caps (section 3.1) were reasoned per enemy, not cross-checked in combination** beyond the
  chaser ceiling of 6.

## What the next design window must pick up

In order. Items 1–2 hold the fleet launch for Wave 3 only; Waves 0–2 can start without them.

1. **Owner rulings on the enemy pass.** The document proposes 14 system rules (listed in ticket T-070)
   and all are [CONTESTABLE]. The ones that block enemy tickets from being built right
   ([BLOCKS-FLEET] in the document):
   - F1 floater altitude rule (2.0 u/s vertical easing);
   - F2 body sizes for all 12 enemies;
   - coil's landing target and push duration;
   - Claude's wind-shot numbers (as written they are unanswerable on open walkways);
   - Isagi not winding up along a flat in-line walkway (F6).
   Without these, T-030, T-031, T-033, T-035, T-037, T-038 and T-040 each invent a number.
2. **Dispatch T-070** (document ticket, DeepSeek V4.1) once the owner has ruled, then T-071 and T-072
   beside T-027 in Wave 2, T-073–T-076 with Wave 4. T-070 must merge before Wave 3 starts.
3. **Two items are parked for the owner, not resolved**: P1 Isagi's `lane` fallback (the clean fix
   changes D-056, which is FINAL) and P2 the nuke's "break line of sight" answer on terrain with
   almost nothing overhead. Both are in the parked table at the end of the enemy document.
4. **The 17 [POST-RUN] preflight items are still open** (`research/fable-preflight.md`, items 8–23).
   This pass proposes resolutions for 8, 17 and 18, and gives a second reason to change Wet Floor
   (item 15). The other thirteen are untouched. Items 10–16 are data-only and should be done before
   the first human playtest (fun risk 10).
5. **T-080 run telemetry log** (fun-risk document) should go into Wave 2. It is small and it makes
   eight of the ten fun signals free from the first bot batch.
6. **Known generator risk, unchanged**: about 45% of levels need a re-roll and the worst attempt seen
   is 11–12 against the limit of 12 (DECISIONS Handover, checkpoint 8). Expect that check to fail
   about once per 30,000 levels. Fix in the generator after the run; never raise the limit.
7. **Three things in the fun audit need the owner because they touch canon or a ruling**: the 5 s
   loading minimum on every restart (risk 1), the 0.1 u mine bypass margin (risk 8), and whether a
   baseline off-screen threat indicator is acceptable (risk 2).

## What I would not trust without checking

- Any "yes" in the counter-play table of the enemy document: it is a prediction until T-075 runs.
- The claim that hurdling a chaser is learnable: it rests on F1 and F2 being accepted as proposed.
- The measured route times (22 / 43 / 77 s): greedy route at run speed on 12 seeds per level,
  ignoring jump and dodge time. They show the order of magnitude, not the real black-phase time.

## Budget used in the whole window

Inkling 2 Small: 5 tasks. GLM 5.3 Flash: 3 tasks. DeepSeek V4.1: 4 tasks. Opus 5.5: 0.
This last pass used no delegates — it was design judgment, written by the lead.

---

# Addendum — ticket-completeness pass and overnight run plan (2026-11-16, later the same day)

Read this part LAST; it supersedes "what the next design window must pick up" above where they differ.

## What this pass completed

| artifact | state |
|---|---|
| `research/fable-tickets.md` §1 — animation specs for all 12 enemies (states, frames, loop, tick timing bound to the DESIGN.md cues) | complete |
| `research/fable-tickets.md` §2 — VFX: tripmine deception rule, glitched floor, beacon closed/open, charge pips + Last Light icon + death attribution screen, void fall and respawn | complete |
| `research/fable-tickets.md` §3 — sound briefs: 37 enemy cues + 13 system cues, cue-first, all synthesized | complete |
| `research/fable-tickets.md` §4 — FLEET_PACK sweep: 27 dispatch addenda (the line each ticket was missing) | complete, with one stated limit (below) |
| `research/fable-tickets.md` §5 — full specs for T-070 (rewritten to the owner's plan), T-080–T-087, backlog T-090–T-096; the standing clause | complete |
| `FLEET_PACK.md` §9A — the new tickets with model assignments; five [CONTESTABLE] notes instead of edits | appended |
| `FLEET_PACK.md` §10 — the overnight run plan (rules R1–R10, mandatory steps a–f, optional backlog) | appended |

Nothing was cut mid-section. Nothing was dispatched. Nothing was committed: `FLEET_PACK.md` is modified
and four files under `research/` are new, all uncommitted. Existing tickets (§0–§9) and every FINAL
decision are untouched; DESIGN.md, DECISIONS.md, TERRAIN_SPEC.md, ENEMIES.md and all code are as at
`14be164`.

## Honest limits of this pass

- **The sweep (§4) was done from my reading of FLEET_PACK.md, not a fresh line-by-line diff.** It
  found 27 gaps; I do not claim it found all of them. The standing clause tells workers to log any
  further gap as a [CONTESTABLE] DECISIONS entry before coding it.
- **Every number in §1–§4 that no earlier document stated is my proposal**, marked [CONTESTABLE]
  where introduced: the 0.5 s spawn fade, all effect sizes and particle rates, the camera and key
  bindings (T-082 — no earlier document specified a camera at all), model dimensions, the stat list.
- **Three ENEMIES.md sound lines name existing recordings** (Big Ben's chime, Isagi's voice lines and
  shot sound, the Roblox tripmine explosion). They get synthesized stand-ins under the TBD fallback
  and are flagged `tbd_audio`. The owner must decide what replaces them.
- **Tripmine particles**: the pass brief said "readable at distance"; DESIGN.md §3.3 fixes the tell at
  12 u. I kept DESIGN.md (constant emitter, readable from 12 u) and noted the wording difference.
- **T-070's rules are not all owner-ruled.** The run plan says "as ruled by the owner"; DECISIONS.md
  holds no ruling on the 14 proposals of the enemy pass. T-070 therefore applies the Isagi and nuke
  items as the owner's rulings and logs every other item as [CONTESTABLE]. My readings of the two
  rulings (both a volley gap AND a 4 s dwell limit for Isagi; a 6 s life per salvo for the nuke) are
  themselves marked [CONTESTABLE].
- **Two rules conflict and I did not edit either**: FLEET_PACK §1 lets a twice-failed Inkling ticket
  go to GLM once; the owner's rule for tonight says an Inkling ticket never goes to GLM. §10 R2 states
  that tonight's rule wins and such a ticket is split or parked.
- **The run plan has never been executed.** Its ordering puts telemetry (step c) and the fun signals
  (step d) after all build tickets, as the owner specified, so the difficulty probe T-060 runs before
  the log exists.

## What the next design window must pick up

1. Read RUNLOG.md, PARKED.md, TBD.md and AUDIT.md from the night. PARKED.md is the design queue.
2. T-081's first report block (terrain-caused vs enemy-caused charges and deaths) is the first real
   evidence about fun risk 3; the level-length block answers fun risk 4.
3. Rule on the [CONTESTABLE] entries T-070 logged (expected D-064 upward).
4. The 17 [POST-RUN] preflight items (`research/fable-preflight.md` 8–23) are still open, minus what
   T-070 covers (8, 15, 17, 18).
5. Replace the three TBD audio stand-ins and any TBD sprites (the 17 images must be in
   `assets_src/enemies/` before the run for real sprites to exist).
6. The known generator risk is unchanged: the re-roll check H15 should fail about once per 30,000
   levels; backlog ticket T-093 will report it if it runs — fix in the generator, never the limit.
