# ENEMIES.md — VOIDWRAP_RUN enemy rework

VOIDWRAP_RUN — enemy rework with PNG models. Every Nullscape enemy is copied 1:1 in behavior, renamed, and rebuilt with PNG models and PNG frame animations. Sounds are NOT copied: every enemy gets a brand-new sound design matched to its new model. Like Nullscape, all enemies are client-sided — including gin ichimaru's spears: rendered on the client, not the server.

## Overview

| Nullscape | VOIDWRAP_RUN | Model | PNG frames |
| --- | --- | --- | --- |
| Mart | kiwi cat | Kiwi cat meme (with Zespri sticker) | 1 |
| Springer | coil | Metal spring / coil | 5 (animation) |
| Bell | thicc ben | Big Ben | 1 |
| Guardian | Isagi | Isagi Yoichi (Blue Lock) shooting | idle → shoot |
| ICBM | nuke | ICBM missile coming down, booster effects | 4 (looping) |
| Husk | YOU?! | Player model, but corrupted | 5 (cycling) |
| Tripmine | gift Larper | Same tripmine model as Nullscape | 5 (cycling, turning) |
| Flesh | toucher | Corrupted 🫵 + corrupted floor | 3 + 5 |
| Baby | seal | Seal | 1 + dash frames |
| Operator | address me | "Address me" elephant meme | 2 (normal → explode) |
| Cadence | Claude | Claude logo + clawd Crab plushie pickups | 3 (plushie idle) |
| Voidbreaker | gin ichimaru | Gin Ichimaru (Bleach) launching sword spears | idle + launch |

Behavior reference for the 1:1 copy: [Nullscape enemy guide — all 18 entities](https://www.ofzenandcomputing.com/nullscape-enemy-guide/) · [Nullscape Wiki](https://nullscape.wiki) · [Enemies — NULLSCAPE Wiki (Fandom)](https://nullscape.fandom.com/wiki/Enemies)

## 📎 Attachment mapping (exact filenames — attach in 3 batches of max 8)

File names must be written EXACTLY as below (including the typos — these are the real filenames). Reference attached images with BOTH the number and the actual file name.

**BATCH 1 (Images 1–8):**

- Image 1 = "kiwicat.png" — kiwi cat: the base model (curled kitten with Zespri Kiwi sticker, transparent background)
- Image 2 = "springer.png" — coil: the metal spring/coil model reference
- Image 3 = "thiccben.png" — thicc ben: the Big Ben model reference
- Image 4 = "isagi_idle.jpeg" — Isagi: idle pose
- Image 5 = "ISAGI_SHOOT.webp" — Isagi: shooting pose (launches the ball)
- Image 6 = "blueballprojectile.webp" — Isagi: the ball projectile
- Image 7 = "NUKE.jpeg" — nuke: the ICBM missile descending, booster effects
- Image 8 = "character to be corrupted.png" — YOU?! (Husk): the base character to apply corruption flickering over

**BATCH 2 (Images 9–16):**

- Image 9 = "tripine.png" — gift Larper: the tripmine model (filename typo is intentional, keep it)
- Image 10 = "toucher.jpeg" — toucher: the corrupted 🫵 pointing finger
- Image 11 = "glitchedground.jpeg" — toucher: the corrupted/glitched floor
- Image 12 = "babehseal.webp" — seal: the baby seal base model
- Image 13 = "address me elephant.png" — address me: the "Address me" elephant meme (normal frame)
- Image 14 = "explosionsffect.jpg" — address me: the explosion frame (filename typo is intentional, keep it)
- Image 15 = "claudelogo.png" — Claude: the Claude logo (main enemy model)
- Image 16 = "gin idle.png" — gin ichimaru: idle pose

**BATCH 3 (Image 17):**

- Image 17 = "ginsword.png" — gin ichimaru: the sword/launch pose

## 🥝 Mart → kiwi cat

**Behavior (1:1):** slowly follow the player, death on contact.

**New sound:** cat meow when near player.

**Model:** kiwi cat — 1 base PNG.

**Attached PNGs:** Image 1 = "kiwicat.png".

## 🌀 Springer → coil

**Behavior (1:1):** jumps between platforms, aiming at where you are, not where you will be; the pre-jump cue gives away its landing zone.

**New sound:** classic spring "boing" before every jump, metallic twang on landing.

**Model:** metal spring / coil.

**Animation:** 5 PNGs — squash → extend cycle (compressed on landing, fully extended at jump apex).

**Attached PNGs:** Image 2 = "springer.png".

## 🔔 Bell → thicc ben

**Behavior (1:1):** teleports directly to the closest player; an audio cue lands about half a second before it appears. Constant movement breaks the teleport lock. If the player touches it, their screen becomes blurred and they get ejected into the air and the bell rings.

**New sound:** the real Big Ben bell chime (Westminster bongs) before each teleport.

**Model:** Big Ben — 1 PNG (teleport handled with VFX).

**Attached PNGs:** Image 3 = "thiccben.png".

## ⚽ Guardian → Isagi

**Behavior (1:1):** fires rapid projectile bursts in your direction; an audio cue precedes each burst, short cooldown between bursts. Time your movement between bursts.

**New sound:** direct shot voice lines, Isagi shoot sae math final shot gun-shot sound when shooting.

**Model:** Isagi Yoichi (Blue Lock) shooting.

**Animation:** idle → shoot (no separate prepare frame exists — use the idle pose with a wind-up telegraph/flash, then the shoot frame).

**Attached PNGs:** Image 4 = "isagi_idle.jpeg" (idle), Image 5 = "ISAGI_SHOOT.webp" (shoot), Image 6 = "blueballprojectile.webp" (the ball projectile).

## 🚀 ICBM → nuke

**Behavior (1:1):** ranged entity firing tracking missiles; a warning cue that speeds up as the missile closes in. Break line of sight. (In Nullscape, ICBM stands for "Inter-Continental Ballistic Mart" 🥝.)

**New sound:** new lock-on beep design speeding up as it closes, rocket-booster roar while the missile descends, deep boom on impact.

**Model:** ICBM / nuke missile PNG coming down, with fire effects on the booster.

**Animation:** 4 looping PNGs — missile descending, booster flame flickering frame by frame (build from the base + flame overlays).

**Attached PNGs:** Image 7 = "NUKE.jpeg".

## 💀 Husk → YOU?!

**Behavior (1:1):** slow mover that creates shockwave rings that kill instantly when it gets close; a corrupted rumble ~1.5s before every shockwave. Jump the rings as they expand.

**New sound:** quiet corrupted static + reversed glitch screech building up before each shockwave — like the player model screaming through the corruption.

**Model:** the player model, but corrupted — a glitched copy of YOU.

**Animation:** 5 PNGs cycling (running animation with jump and everything) — corruption glitch flickering applied over the base character.

**Attached PNGs:** Image 8 = "character to be corrupted.png" — the base: "this image but with corruption flickering".

## 💣 Tripmine → gift Larper

**Behavior (1:1):** stationary hazard, same as Nullscape — detonates when triggered by a player stepping on it.

**New sound:** Roblox tripmine explosion sound effect.

**Model:** the exact same tripmine model as Nullscape.

**Animation:** 5 PNGs cycling — the tripmine turning/rotating with its light pulsing.

**Attached PNGs:** Image 9 = "tripine.png".

## 🫵 Flesh → toucher

**Behavior (1:1):** creates glitched floor tiles that slow the player and lock abilities while they stand on them; its body kills instantly on contact; an audio cue plays whenever new glitched tiles appear. Avoid the glitched zones entirely.

**New sound:** corrupted squelch — wet glitch gurgle and digital distortion as the floor becomes corrupted.

**Model:** corrupted "🫵" pointing finger — 3 PNGs flickering back to back — and the floor around it becomes corrupted: glitched, corrupted-looking floor, ~5 PNGs cycling.

**Attached PNGs:** Image 10 = "toucher.jpeg" (the finger), Image 11 = "glitchedground.jpeg" (the corrupted floor).

## 🦭 Baby → seal

**Behavior (1:1):** small, fast, kills instantly on contact; ~1s high-pitched cry before it attacks. VOIDWRAP_RUN: the cry is replaced by a real seal bark when it dashes — it opens its mouth and flaps.

**New sound:** actual seal barks (arf arf) on the dash, wet flipper flaps while it moves.

**Model:** baby seal — 1 base PNG + dash frames (mouth open, flapping — build dash frames from the base with overlays).

**Attached PNGs:** Image 12 = "babehseal.webp".

## 🐘 Operator → address me

**Behavior (1:1):** Nullscape Operator fires projectile spreads from a distance with a ~2s charging cue. VOIDWRAP_RUN mechanic: it spawns, and you have 5 seconds to stand still — if you do not stand still, it explodes and kills you.

**New sound:** elephant trumpet on spawn, low rumbling build-up during the 5 seconds, massive boom on the explode frame.

**Model:** "Address me" elephant meme (the elephant in the room).

**Animation:** 2 PNGs — normal → explode.

**Attached PNGs:** Image 13 = "address me elephant.png" (normal), Image 14 = "explosionsffect.jpg" (explode frame).

## 🤖 Cadence → Claude

**Behavior (1:1):** musical area attacks — drums = radial shockwaves, strings = sweeping beams, wind = homing projectiles; attacks follow musical timing, so dodge rhythmically.

**New sound:** Claude-themed instrument set — soft UI chimes, keystroke ticks and notification pings for the drums/strings/wind attacks; cute squeak-pop when you pick up a plushie to calm it down.

**Model:** the Claude (Anthropic) logo as the main enemy; pick up clawd Crab to calm it down.

**Animation:** 3 PNGs — the plushies idling.

**Attached PNGs:** Image 15 = "claudelogo.png". Plushie sprite (clawd Crab): use https://github.com/xyc/plushie for the sprite.

## ⚔️ Voidbreaker → gin ichimaru

**Behavior (1:1):** breaks platforms into void zones that kill instantly; a cue warns which platform goes next.

**New sound:** sword "shing" (unsheath) + whoosh when the spears launch, deep cracking rumble before a platform breaks. VOIDWRAP_RUN rework: gin launches his sword as spears (Shinsō-style extension) — the spears are rendered on the client, not the server.

**Model:** Gin Ichimaru (Bleach).

**Attached PNGs:** Image 16 = "gin idle.png" (idle), Image 17 = "ginsword.png" (launch pose).

## ⚙️ Global notes

- All enemies stay server-sided (Nullscape's enemies are all server-sided too) — apart from gin ichimaru and his spears (spears included): rendered on the client, never the server.
- All sounds are brand-new — nothing is copied from Nullscape audio. Each enemy keeps its 1:1 behavior and cue timing (wind-up, warning, cooldown), but the audio itself is redesigned to match the new PNG model — see the "New sound" line on each enemy.
- For the Tripmine's exact Nullscape look, screenshot the model straight from Nullscape.
- Multi-frame animations (coil, ICBM, Husk, tripmine, toucher, floor): build the frames from one base PNG + effect overlays (flame, glitch) rather than hunting 5 separate images — it keeps the style consistent.

## 🔒 Hard rules (owner-set, never negotiable)

- BILLBOARDING: all PNG enemies always face the player — the sprite is rendered on the client, rotating to face the viewer at all times (like Evade-style entities on Roblox). Enemies are never seen edge-on or from the side; there is no "side" of a PNG enemy.
- HITBOXES: an enemy's hitbox covers ONLY the actual body/person/object in the PNG — never the image file's transparent padding, corners, or margins. If the PNG is 512×512 but the cat occupies 300×400, the hitbox is the cat.
- TRANSPARENCY: every PNG asset must have a fully transparent background — no white/colored squares or padding may ever render around a model. Validate each asset in a test scene against the game's fog and palette.
- DISCLAIMER (required in README + about screen): this is a personal, non-commercial project with no money involved. It is not affiliated with, endorsed by, or connected to any person, brand, character, or IP referenced or depicted in the game.
- TBD FALLBACK: if any agent refuses or is blocked from adding a specific enemy/name/asset (e.g. a copyrighted character), it must NOT stall the ticket — immediately proceed with name "TBD" and a placeholder TBD PNG, wire the full behavior, and mark the entry TBD for later replacement. The run never stops for a refusal.