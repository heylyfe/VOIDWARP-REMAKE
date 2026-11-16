# Nullscape — Research Patterns

Facts only, from the sources listed. Facts are paraphrased/quoted from source pages; "no number given" means the source states none. Wiki mechanics marked `[wiki]` refer to nullscape.wiki pages (article wikitext and `Module:GameData/*.json` data used for prices/levels/stacks); `[ofzen]` = ofzenandcomputing.com guide. Raw fandom wiki was not readable.

## 0. Fetch log

| URL | Status |
|---|---|
| https://nullscape.wiki/Curses | REACHED |
| https://nullscape.wiki/Upgrades | REACHED |
| https://nullscape.wiki | REACHED (Main Page; lists nav to Enemies/Classes/etc.) |
| https://www.ofzenandcomputing.com/nullscape-enemy-guide/ | REACHED (403-style content not hit; full text retrieved) |
| https://nullscape.fandom.com/wiki/Enemies | UNREACHABLE (HTTP 403 via webfetch; retry with `curl -A "Mozilla/5.0"` also returned 403) |

Supplementary pages also read for sections 5–6 (all nullscape.wiki, all REACHED): /Enemies, /Mart, /Springer, /Bell, /Guardian, /ICBM, /Husk, /Flesh, /Baby, /Operator, /Cadence, /Voidbreaker, /Tripmines (redirect from /Tripmine), /Classes, /Beacon, /Gifts, /Void, /Difficulty, /Progression_Events, /Gold_Gifts, /Tripcoins, /Lobby_Sizes; plus `Module:GameData/Curses.json`, `Upgrades.json`, `Enemies.json` via `https://nullscape.wiki/w/index.php?title=Module:GameData/<file>&action=raw` and article wikitext via `…/w/api.php`. Note: `nullscape.fandom.com` content is unverified; nothing in this file is sourced from it.

## 1. Curses — raw table

Source: https://nullscape.wiki/Curses (list) + `Module:GameData/Curses.json` (level/req/stack/values). min_level of -1 in the data is shown as "None". "Pool removal: Yes*" = standard rule (§2); stackable picks remain until max stacks. Dev/removed/unused rows are not obtainable in normal play.

### Global curses (no requirement beyond level)

| Name | Effect (one sentence) | Min level | Enemy req | Stackable | Pool removal |
|---|---|---|---|---|---|
| Lower Gravity | Lowers player gravity ~14% (15 studs/s²); locks Higher Gravity. | 1 | — | No | Yes* |
| Higher Gravity | Raises gravity 20%, weaker jumps, faster falls; locks Lower Gravity. | 1 | — | No | Yes* |
| Random Spawn | Players and (non-Cadence) enemies spawn at random spots; player gets a temporary platform that vanishes on move/30 s idle. | 5 | — | No | Yes* |
| Scattered Gifts | Gifts/Gold Gifts/Tripmines spawn at random offsets. | 1 | — | No | Yes* |
| Weaker Jump Pads | Jump Pads (and Grapple Points, 30% for Grappler) ~40% weaker boost. | 1 | — | No | Yes* |
| Savory Ring | +0.15x Golden Gift yield (+0.05x per 5th level); spawns random enemies during collapse. | 8 | — | No | Yes* |
| Bigger Tripmines | Tripmines 30% bigger. | 5 | — | No | Yes* |
| More Tripmines | Doubles Tripmine count; two stacks quadruples it (slightly reduces gift count). | 5 | — | Yes, max 2 | Until max |
| High Roller | Altar of Chance rolls stronger/replaced outcomes; locks Tweaked Odds. | 5 | — | No | Yes* |
| Tweaked Odds | Altar of Chance always rolls one positive + one negative; nerfs/removes some positives (−0.25x yield, removes No Tripmines/Revive Player); locks High Roller. | 5 | — | No | Yes* |
| LAP 2 | Beacon needs 40% of Golden Gifts (auto-opens if all tiles collapse); +0.25x yield, halved collapse speed; locks Fragile Gifts. | 8 | — | No | Yes* |
| Fragile Gifts | Collapse speed doubled; +0.75x Golden Gift yield; locks LAP 2. | 8 | — | No | Yes* |
| Nothing? | Shops ~15% cheaper; adds 1 temporary enemy per level every 5 levels (max 8). | 8 | — | No | Yes* |
| Jackpot | Rolls a single Altar of Chance outcome at level start. | 10 | Requires curses High Roller + Tweaked Odds | No | Yes* |
| Barotrauma | Seamines 20% bigger; much stronger knockback. | 15 | Seamines (level 10) | No | Yes* |
| Minefield | 50% more Seamines (100% at 2 stacks). | 15 | Seamines (level 10) | Yes, max 2 | Until max |
| Run | Seamines chase the player who touched them. | 15 | Seamines (level 10) | Yes, max 1 | Until max |
| Volatile Implosions | 50% more Void Implosions; they implode faster. | 15 | Void Implosions (greater curse) | No | Yes* |
| Beacon Mirage | Beacon spawns at random position; on open, fake beacons inflict Insanity (20 s) on touch; real beacon brighter. | 25 | — | No | Yes* |

### Enemy curses (appear only if the enemy is in the run; Concussive Blast is listed in both Wiki tabs)

| Name | Effect (one sentence) | Min level | Enemy req | Stackable | Pool removal |
|---|---|---|---|---|---|
| Concussive Blast | Seamines also concuss (2 s; jumping uses all jumps) and overtune (10 s); overtuned makes Bell rings deadly. | 10 | Bell | No | Yes* |
| More Ringing | Bell rings when enemies touch it; Bell's teleport cooldown reduced. | 1 | Bell | No | Yes* |
| Mighty Gong | Bell bigger; its teleport emits a shockwave that pushes players, counting as a direct ring. | 1 | Bell | No | Yes* |
| Concussion | Ringing Bell inflicts concussion (7 s; jumping uses all jumps). | 1 | Bell | No | Yes* |
| Bigger Marts | Mart 1.5x size/cap; spawns an extra Mart on level start. | 1 | Mart | No | Yes* |
| Mart Infection | Player death spawns a Mart (Solo/Duo: one per 4 temporary enemy stacks); extra Mart on level start. | 8 | Mart | No | Yes* |
| Red Marts | Each Mart gets a Red Mart that explodes near players; respawns after exploding. | 1 | Mart | No | Yes* |
| Beacon Imp | On beacon open, a random Mart becomes the beacon and avoids players (Mirage splits all Marts). | 18 | Mart | No | Yes* |
| Problem Child | Baby sometimes faints its dash (laugh cue) then follows with a longer, faster dash. | 5 | Baby | No | Yes* |
| Big Baby | Baby bigger; dash distance and speed up. | 1 | Baby | No | Yes* |
| Baby Steps | Baby gains an extra dash (2 on Extreme). | 5 | Baby | No | Yes* |
| Scorched Earth | ICBM leaves a fire pool after exploding; touching sets you on fire (7 s; forced run). | 1 | ICBM | No | Yes* |
| Bigger Blast | ICBM explosion radius +30%. | 5 | ICBM | Yes, max 1 | Until max |
| Magic Missile | ICBM fire pools inflict a random debuff (Flesh/Concussion 3.5 s/Insanity/Fire 7 s). | 1 | ICBM + Scorched Earth (curse) | No | Yes* |
| Incendiary Shrapnel | ICBM emits fireballs in 6 directions after exploding; fire on touch (5 s). | 1 | ICBM | No | Yes* |
| Closer Husk | Time between Husk spawns decreased (locks Further Husk). | 1 | Husk | No | Yes* |
| Further Husk | Time between Husk spawns increased (locks Closer Husk). | 1 | Husk | No | Yes* |
| Taller Husk | Husk grows taller/wider at levels 10/25/50 progression events. | 1 | Husk | No | Yes* |
| Husk Express | Husk gaps are filled in; players can't fit between Husks. | 5 | Husk (2 stacks) | No | Yes* |
| Resonating Shockwaves | Springer shockwaves inflict Overtuned (15 s) + direct-ring status effects. | 5 | Springer + Bell | No | Yes* |
| Springloaded | Every 2nd Springer jump leaves a shockwave; landing shockwave larger and launches farther. | 5 | Springer | No | Yes* |
| Seahorse | Springer sometimes lands on Seamines. | 15 | Springer | No | Yes* |
| Horse Skipping | Springer quickly jumps again every 3rd jump (~1 s stand still). | 5 | Springer | No | Yes* |
| Bloodier Meat | Flesh infects tiles from much farther away. | 5 | Flesh | No | Yes* |
| Airborne Flesh | Flesh can infect Springers, Jump Pads, Grapple Points; infected Springers spread flesh. | 5 | Flesh + Springer | No | Yes* |
| Camouflage | Guardian invisible while moving, untrackable by Radar; projectile speed up. | 8 | Guardian | No | Yes* |
| Shotgun | Guardian fires a spread of bullets instead of a volley; bullet size up. | 5 | Guardian | No | Yes* |
| Ambush | Telefragger sometimes teleports behind you with a dash. | 8 | Telefragger | No | Yes* |
| Accurate Telefragger | Telefragger sometimes predicts vertical movement. | 1 | Telefragger | No | Yes* |
| Lost Embers | Kolóna no longer shows its countdown number. | 1 | Kolóna | No | Yes* |
| Burning Bouquet | Kolóna attracts Razorbloom whenever it appears. | 1 | Kolóna + Razorbloom | No | Yes* |
| Angry Bird | Razorbloom instantly starts screaming on landing. | 1 | Razorbloom | No | Yes* |
| Smart Little Bird | Razorbloom appears at start of Oblivion and stays until it ends. | 1 | Razorbloom + Oblivion | No | Yes* |
| Stronger Wings | Longer Razorbloom is active → lower gravity. | None | Description references Razorbloom; no req field in data | No | Yes* |
| Blade Carousel | Voidbreaker's swords spin around you before firing (predict-position trap). | 5 | Voidbreaker | No | Yes* |
| Corrupted Blades | Voidbreaker fires an extra volley with 3 fake swords (2 on Casual); fakes don't damage but inflict Insanity (15 s). | 1 | Voidbreaker | No | Yes* |
| Deadly Melody | A Cadence creates an instrument whenever a player dies (one Cadence only). | 1 | Cadence | No | Yes* |
| Jumping Instruments | Every 3rd instrument created is on a Springer; that Springer jumps slower. | 15 | Cadence + Springer | No | Yes* |
| Encore | Beacon requires all instruments; Cadence creates several on collapse; instrument tiles can't collapse. | 15 | Cadence | No | Yes* |
| Alluring Arrangement | Cadence chains a player to an instrument, dragging them toward it. | 1 | Cadence + Bell | No | Yes* |
| Leo | Sigil's beams become bigger. | None | Sigil | No | Yes* |
| Sagittarius | Sigil shoots tendrils at tiles, creating heat waves that set players inside on fire (7 s). | 1 | Sigil | No | Yes* |
| Blueprint: Cross Beams | Scrapmaw's lasers form a rectangular grid when firing. | 20 | Description references Scrapmaw; no req field in data | No | Yes* |
| Blueprint: Supersonic Lasers | Scrapmaw's lasers slowly move to the side. | 15 | Scrapmaw | No | Yes* |
| Blueprint: Efficient Coolant | Scrapmaw fires a second set of lasers after the first. | 20 | Scrapmaw | No | Yes* |

### Developer-exclusive curses (dev commands only)

| Name | Effect (one sentence) | Min level | Enemy req | Stackable | Pool removal |
|---|---|---|---|---|---|
| only highrise tiles | Levels consist only of highrise towers. | None | — | No | n/a |
| only ice tiles | Levels consist only of ice tiles. | None | — | No | n/a |
| only garden tiles | Levels consist only of garden tiles. | None | — | No | n/a |
| You Need Me | Husk becomes a multi-headed creature. | None | Husk | No | n/a |
| Fear | Spawns an enemy that chases the player's camera and kills on touch. | None | — | No | n/a |

### Removed curses (no longer accessible)

| Name | Effect (one sentence) | Min level | Enemy req | Stackable | Pool removal |
|---|---|---|---|---|---|
| Worse Tiles | Removes smaller tiles from map generation. | None | — | No | n/a |
| Ice Biomes | Allows Ice Biomes to generate. | None | — | No | n/a |
| Crayonify | All enemy sprites are replaced by crayon doodles. | 8 | — | No | n/a |
| CONTENT REMOVED | Per NIL, two better-homing, faster fakes spawn and impair vision on hit. | 5 | NIL | No | n/a |
| Idiotware | If Kookoo appears as a black smiley, the player must not use abilities. | 10 | Kookoo | No | n/a |
| Cheeseware | Kookoo triggers Doombringer to activate. | 10 | Kookoo | No | n/a |
| Pixelate | Permanently pixelates the player's screen. | None | — | No | n/a |
| Nearsightedness | Adds a vignette around the player's vision. | 5 | — | No | n/a |
| Windows GUI | Adds a Windows border frame, obstructing vision, smaller camera. | None | — | No | n/a |
| REDACTED | Every 4th NIL dash → NIL chases with big speed boost for 10 s. | 8 | NIL | No | n/a |
| Cognitive Dissonance | NIL's 4th attack: chase + fake copies that inflict Insanity. | 8 | NIL | No | n/a |
| Delusion | Temporary enemies no longer appear in the topbar. | None | — | No | n/a |

### Unused curses (scrapped pre-implementation)

| Name | Effect (one sentence) | Min level | Enemy req | Stackable | Pool removal |
|---|---|---|---|---|---|
| Pursuit | Ponderer always creeps toward nearest player; kills even through shields. | None | Ponderer | No | n/a |

## 2. Curses — system rules (source: https://nullscape.wiki/Curses)

- Curses are debuff-style modifiers; some have positive/mixed effects. Icon border is pink (#FF00EF).
- 64 obtainable + 18 unobtainable/removed = 82 total Curses as of Patch 5.1.
- Most curses have a minimum level requirement or another prerequisite (an enemy, or sometimes other curses/greater curses). Enemy curses appear only if their enemy is in the run; whether they affect Voidbound counterparts varies per curse.
- Picking a curse removes it from the pool; some curses can be stacked multiple times instead.
- Permanent curse shops appear on even-numbered levels, presenting 3 pedestals; a pick is mandatory to continue, and choices can be re-rolled.
- Curse shop appears after Enemies and before Upgrades (if present); it does not appear if Greater Curses selection is present.
- Rerolls start at 3, +1 additional reroll every 7 levels.
- Greater Curses exist separately; they are less frequent, drastic, and cannot be removed by the Altar of Purification. Some curses are Chaos Mode exclusives (listed on the Chaos Mode page, not the Curses page).
- The Altar of Purification can remove curses; removed curses return to the curse pool.
- Temporary curses: expire after a number of levels (variable, usually shown when gained, e.g. Medal/Altar of Curses); can be lengthened/shortened by delusions Perseverance/Ignorance. Shown half-transparent in the top bar with hover timer; Fast Track counts skipped levels as passed levels.
- Temporary curses do not count toward requirements for other content (e.g. temporary Scorched Earth doesn't unlock Magic Missile).
- Altar of Purification auto-cleanses temporary curses at no cost, but has a limit on how many it can remove; it does not prevent re-appearance — re-picking makes it permanent.
- Temporary curses become permanent by default via Overconfidence; normally obtained via Medal, Altar of Curses, Mania, Altar of Perfection.
- Temporary curses are obtained alongside permanent ones; some permanent curses can also be obtained via Desire or Medal curse picks under Overconfidence.
- Curses can also be obtained mid-run via Altar of Chance rolls (High Roller/Tweaked Odds interact with it, e.g. Jackpot).

## 3. Upgrades — raw table

Source: https://nullscape.wiki/Upgrades (list) + `Module:GameData/Upgrades.json` (cost/max_stack/min_level/req). Price notation: `s` = solo, `m` = multiplayer; base = first difficulty (Casual) first stack unless noted; Standard/Extreme values are higher — full per-difficulty arrays are in the JSON. Many prices are per-stack and rise per stack; this is summarized. Categories are assigned by the researcher (the source does not categorize): economy = yield/payout; mobility = movement/jump/flight/grapple; protection = survive hits/void/tripmines; information = radar/tracking; utility = collection range, class helpers, odd effects; other = anything else.

### In-game upgrades (all difficulties)

| Name | Effect (one sentence) | Price | Stacks | Category |
|---|---|---|---|---|
| Better Jump Pads | More jump pads with less random positioning. | 50 | 1 | mobility |
| Paycheck | +40 Golden Gifts if ≥half the lobby survives (Solo +50; Duo +40 +10/survivor). | 33s/55m base | 5 | economy |
| Business License | +0.25x Golden Gift yield. | 50s/75m base (Casual) | 2 | economy |
| Swiftness Ring | +10% movement speed per stack (Charger: turn speed; Wanted 18%). | 60s/70m base | 3 | mobility |
| Grapple Points | Semi-random red-sphere jump/grapple targets with stronger boost (Grappler: longer reel, no cooldown). | 100 | 1 | mobility |
| Medal | Collapse spawns a Medal; deliver to beacon for Golden Gifts + option to pick a harder temporary curse; carrying it gives an extra double jump but disables abilities. | 100 | 1 | economy |
| Tria Orbs | Orbs appear around the map; exiting refills jumps and gives momentum facing. | 100 | 1 | mobility |
| Double Jump | Extra airborne jump (Wanted: two; Glider: cancels glide). | 125s/150m base | 1 | mobility |
| Radar | Gift arrow always appears; nearby gifts highlighted. | 100s/125m base | 1 | information |
| Radar Module: Enemies | Enemies get a visible box + name through walls. Req: Radar. | 125s/150m base | 1 | information |
| Radar Module: Altars | Unused altar locations marked every 12 s. Req: Radar. | 200s/250m base | 1 | information |
| Altar Boons | Paycheck reward +20% per altar used that level. Req: Paycheck. | 450s/475m base | 1 | economy |
| Star Marts | Star Marts can spawn; touching gives speed, +2 gift range, debuff immunity 25 s. Req: Mart. | 300 | 1 | utility |
| Spring Shoes | 1.4x jump height while quick-turning or standing still. Req: Springer. | 100 | 1 | mobility |
| Fanny Pack | Collapse: some tiles turn yellow; collecting all gifts on them grants bonus Golden Gifts. | 250 | 1 | economy |
| Grace Wings | Greatly enhanced mid-air control. | 200s/300m base | 1 | mobility |
| Pocket Bell | Extra double jump with Bell-style visuals. Req: Double Jump + Bell. | 300 | 1 | mobility |
| Ice Skates | Less slipping on ice; sustained one-direction movement slowly grants speed. | 250s/300m base | 1 | mobility |
| Helmet | Bonking launches you upward with movement control (class-specific bonuses). | 275s/300m base | 1 | mobility |
| Advanced Gravity Coil | +25% max jump height; controllable jump height (Wanted: 35%). | 500 (Casual m); 600/650s/725m Standard–Extreme | 1 | mobility |
| Birthday Pony | Springer collects gifts it lands on. Req: Springer. | 250s/300m base | 1 | utility |
| More Altars | One extra altar spawns (doesn't raise altar caps). | 400s/450m base | 1 | utility |
| Subspacial Barrier | Take an extra hit from Tripmines/Void Implosions (discarded per level). Req: 3× Defuse Kit. Min 10 (Std/Ext), 15 (Casual). | 400s/600m base | 2 | protection |
| Larger Grapple Points | Grapple Points 25% larger. Req: Grapple Points. | 250s/300m base | 1 | mobility |
| Ninja Belt | Class-specific empowered alternate ability ([ALT-ABILITY]). Min 13. | 400s/450m base | 1 | utility |
| Propeller Hat | Double jump while bonked (uses all jumps); Bell rings and Springer shockwaves replenish jumps. Req: Helmet. | 550s/650m base | 1 | mobility |
| Radar Module: Instruments | Marks Cadence's instruments every 12 s + arrow to nearest. Req: Radar + Cadence. | 500s/600m base | 1 | information |
| Shark Tail | Class-specific alternate alt-ability mode. Req: Ninja Belt. | 650s/900m base | 1 | utility |
| Shield | Extra hit (not the Void). Min 15. | 1500s/2000m base | 1 | protection |
| Sport Shoes | +40% move speed (Wanted +50%). Min 15. | 750s/1000m base | 1 | mobility |
| Shadow Cloak | Phase through players, small decor, some big decor, mid-air Springers. Min 15. | 1500s/2000m base | 1 | utility |
| Gift Magnet | +0.5 studs gift range per stack. Min 15. | 500s/750m base | 3 | utility |
| Matrix Tetrahedron | Instant ground acceleration; removes slippery movement. Min 15. | 1250s/1500m base | 1 | mobility |
| Fleeting Fate | On collapse: +40% speed, gift range, debuff immunity 40 s. Locks Panic Necklace. Min 18. | 1500s/1750m base | 1 | utility |
| Panic Necklace | When your last shield breaks: speed, +2 gift range, debuff immunity 40 s. Req: Shield; locks Fleeting Fate. Min 18. | 1500s/1750m base | 1 | protection |
| Aggro Magnet | +0.1 studs gift range per enemy targeting you (max +1). Req: Gift Magnet; locks Debuff Magnet. Min 15. | 1500s/1700m base | 1 | utility |
| Debuff Magnet | +0.25 studs gift range if you have a debuff, ×2 per extra debuff. Req: Gift Magnet; locks Aggro Magnet. Min 15. | 1500s/1700m base | 1 | utility |
| Miniature Hourglass | Class-specific empowered passive (cooldowns/range/rate). Req: Ninja Belt. Min 20. | 3000s/3000m base | 1 | utility |
| Gift Idol | +1% chance per stack that a collected gift also collects nearby gifts. Req: Gift Magnet. Min 20. | 2000s/2500m base | 5 | economy |
| Drowned Ægis | Altar of Protection also grants one-time Void shield (teleports you out of the Void); makes Altar of Protection always spawn. Req: More Altars. Min 20. | 3250s/4000m base | 1 | protection |
| Jet Boosters | Double jumps redirect momentum toward where you're facing. Req: Scrapmaw. Min 25. | 4000s/4500m base | 1 | mobility |
| Magnified Levels | Levels become smaller; size ÷ 1.x per stack. Min 30. | 1500s/2000m base | 3 | utility |
| Quixotic Wing | +1.5 s flight (hold jump). Does not apply to Blossom. Min 30. | 25000 (Casual) | 1 | mobility |
| Transient Pennon | +1.5 s flight (hold jump). Does not apply to Blossom. Min 30. | 25000 (Casual) | 1 | mobility |
| Blossom | Fly ~3 s by holding jump. Min 40. | not stated in data | 1 | mobility |

### Exclusive upgrades (certain difficulties/player counts/events)

| Name | Effect (one sentence) | Price | Stacks | Category |
|---|---|---|---|---|
| Orb | Nothing for most classes; Grappler: longer grapple. | not stated in data | 1 | other |
| Adrenaline | +20% move speed (Glider: +glide speed); Solo/Duo only; replaces Final Stand. Min 3. | 50 | 1 | mobility |
| Defuse Kit | 20% per stack chance for Tripmines not to explode; 3 stacks unlock Subspacial Barrier. (Casual: "Nothing.") Min 4. | 30 | 3 | protection |
| Radar Module: Tripmines | Highlights nearby Tripmines through walls. Req: Radar. | not available on Casual; 300s/350m (Standard); 350s/450m (Extreme) | 1 | information |
| Radar Module: Players | Highlights all players every 12 s (obtained via special means). Req: Radar. | 150 | 1 | information |
| Final Stand | Last one alive: move-speed boost + shield (6 s invincibility). Party/Party+; replaced by Adrenaline in Solo/Duo. Min 8. | 300 | 1 | protection |
| Health Insurance | Paycheck always triggers. Req: Paycheck. Unavailable <4 players or on Extreme. Min 8. | 350 / 500 (two values given) | 1 | economy |
| Soul Tracers | On death, a player drops an orb; collecting it boosts Golden Gift yield (Solo: +0.3x per shield lost). Min 15. | 800 (650/400 on Casual) | 1 | economy |

### Developer-exclusive / removed

| Name | Effect (one sentence) | Price | Stacks | Category |
|---|---|---|---|---|
| War Horse (dev) | Every 2nd jump, Springer targets and detonates a Tripmine. Req: Springer + Birthday Pony. | 10000 | 1 | other |
| Real Wings (removed) | Fly ~3 s holding jump (replaced by Blossom). Min 20. | 25000 | 1 | mobility |

## 4. Upgrades — system rules (source: https://nullscape.wiki/Upgrades)

- Currency: Golden Gifts (also called Gold Gifts). Upgrade icons have an aqua border (#00C8FF).
- Upgrade shops appear on levels ending in 0, 3, 5, and 8, presenting 3 pedestals; the middle pedestal is used to continue.
- A pick is not mandatory; upgrades can be freely re-rolled, removing current choices until the next upgrade shop (forced continue if everything available is re-rolled).
- Availability depends on level + specific requirements (enemies, curses, upgrades). Upgrades stack; a stack at max renders it unavailable.
- Upgrade shop appears after Enemies and Curses (if present), before Greater Curses; shops are skipped if all currently available upgrades have been bought (fewer intermissions on levels ending in 3).
- Price scaling (per run, doesn't scale back down except when more players join): ⌈BasePrice × √PlayerCount⌉. In Party+ the formula becomes ⌈BasePrice × √PlayerCount⌉ / 1.125.
- Pre-Patch 4 formula: ⌊PlayerCount/6 × 10⌋ × 10.
- Tripcoins are a separate currency (shop in lobby; Classes cost Tripcoins, not Golden Gifts). [Source: /Tripcoins]
- 51 obtainable upgrades as of Patch 5.1 (incl. Blossom); ~47 max obtainable per run (58 with stacking).
- Runs started on Casual remove all Tripmine-related upgrades (except Subspacial Barrier); Solo/Duo replace Final Stand with Adrenaline; Health Insurance unavailable <4 players or on Extreme; some stackable upgrades gain an extra stack via Delusions.
- An Altar of Chaos used under Altar of Wishes can grant Aggro/Debuff Magnet or Orb / Radar Module: Players outside normal availability.

## 5. Enemies — behavior numbers

Sources: [wiki article per enemy] = https://nullscape.wiki/<Name>; [ofzen] = https://www.ofzenandcomputing.com/nullscape-enemy-guide/; [gamedata] = Module:GameData/Enemies.json + /Enemies overview; numbers quoted as given. "no number given" where absent. Tripmine is not an enemy — see /Tripmines facts at the end.

### Mart [wiki](https://nullscape.wiki/Mart) [ofzen]
- Floats toward nearest player at 10 studs/second (Extreme: twice as fast, 20 studs/second) — wiki.
- Spawns at size 1; Marts merge on contact — bigger gains the difference; size 6+ Marts show a bubble indicating kill range — wiki. Size scales with progression events (level 6, 12, 18, 24, 30 → larger spawn size & cap) [gamedata][Progression_Events].
- Kills on contact; phases through objects — wiki. Selectable level 1; can be selected after level 15 — wiki. Extreme: increased speed-size bonus — wiki. 2 initial merge… no number given for merge radius/cap — wiki notes max size exists but gives no cap number.
- ofzen: "fast-moving humanoid … dash attacks"; dash startup low whoosh warning; pause before dash is the dodge window; class picks Spirit/Phantom. (ofzen gives no speed number; wiki's 10/20 studs/s is the concrete figure.)
- Counter: keep distance, avoid merging groups, Spread with Random Spawn; Emote next to Mart to slow/halt him — wiki.

### Springer [wiki](https://nullscape.wiki/Springer) [ofzen]
- Jumps to a random spot; arc lands over ~2.75 seconds; idle ~3 seconds before next jump — wiki.
- Landing creates a short but wide shockwave that knocks players away; landing directly on a player kills — wiki. Extreme: shockwaves much more knockback and slightly bigger — wiki (as of Sep 10 2026 no longer creates lethal red shockwave).
- Kills on landing; does not collide with level/other Springers — wiki. Min level 1; max stack 2; true max 10 — gamedata. Shockwave locks abilities "for a few seconds" — no number given — gamedata explanation.
- Counter: small jump as it lands prevents shockwave hit — wiki; "spring coil sound" precedes jumps, giving destination — ofzen; stay mobile, don't linger on one platform — ofzen.

### Bell [wiki](https://nullscape.wiki/Bell) [ofzen]
- Teleports in front of a random player, predicting velocity; inactive ~1.25 seconds (black smoke) before appearing; remains in place ~13.35 seconds before teleporting again — wiki.
- ofzen: teleport sound cue "a half-second before" it appears; sharp chime then spatial distortion; keep moving / circle-strafe.
- On touch: rings — collects gifts touching it, cleanses nearby Light/Heavy Flesh, distorts all players' screens, launches ringer upward; cleanses ringer of flesh — wiki.
- Per-Bell counter tracks rings: −1 per 10 seconds; at 3 rings the player is afflicted with Overtuned (20 s), after which Bell kills on touch — wiki.
- Harmless-ish: hardly kills directly; "one of the only enemies to not be able to directly kill on first touch" — wiki. Min level 1; max stack 1 — gamedata.
- Counter: don't ring it 3 times; negate boost with abilities (all classes except Spirit/Prisoner); ring can be used to cleanse flesh — wiki.

### Guardian [wiki](https://nullscape.wiki/Guardian) [ofzen]
- Min level 8; dashes near players, shoots projectiles; Casual/Standard: 3 projectiles; Extreme: 4 faster projectiles, faster fire rate — wiki/gamedata (max stack 1, true max 8 — gamedata).
- Projectiles only kill on contact; stopped by solid objects or after some time — wiki. Enrages on Altar of Passage (moves/shoots quicker) — wiki.
- ofzen: "rapid projectile bursts"; mechanical whirring before each burst = warning; brief cooldown after burst; audio cue 1–2 s (Priority 2); class Diver recommended. No projectile speed/damage numbers — no number given.
- Counter: move to the side of the volley (not toward/away); zoom out to see indicators; dodge in burst windows — wiki.

### ICBM [wiki](https://nullscape.wiki/ICBM) [ofzen]
- Min level 1; max stack 2, true max 10 — gamedata. Locks a random player (circular indicator), tracks 2.5 seconds, stops and descends, reaches destination after 1.5 seconds, explodes killing players in blast radius; disappears ~5 seconds, then re-locks; multiple ICBMs can share a target; 1 player remaining → waits 4× usual duration — wiki. Casual/Standard: locks directly; Extreme: predicts landing location from movement (imperfect, underestimates speed) — wiki.
- Sphere-shaped blast (avoid even below) — wiki. ofzen: lock-on beeping rises in frequency as missile nears; break line of sight; Diver recommended; "Inter-Continental Ballistic Mart". No damage number given — no number given.
- Blast radius: no number given (Bigger Blast curse +30%) — wiki/curses.

### Husk [wiki](https://nullscape.wiki/Husk) [ofzen]
- Min level 1; client-sided; selection cap 2 (was 3) — wiki/gamedata (max stack 2). Copies every player's movements, killing on touch — wiki.
- On movement detection, waits (4.7 s total) then 3.5 s before indicating location; each Husk stack takes 1.2 s to spawn, following the previous one — wiki.
- Extreme: 2 Husks spawn per stack beside each other, widening hitbox — wiki. Closer/Further Husk adjust pre-indicator duration; Random Husk randomizes spawn distance — wiki. Progression events add husks at 10/25/50/75/100 — Progression_Events.
- ofzen: "slow but creates damaging shockwaves when it gets close"; tremor rumble ~1.5 s before shockwave; jump when ring is at max radius; Husk moves slowly. (ofzen's "shockwave" description conflicts with wiki's mimic behavior; wiki is authoritative for mechanics. ofzen gives no speed number.)
- Counter: constant movement, avoid backtracking; scout with no movement; buy a trail; jumping over possible but hard — wiki. Husk cannot affect another Husk — wiki.

### Tripmine (hazard, not an enemy) [wiki](https://nullscape.wiki/Tripmines)
- Spawns beyond Level 5 (Standard+), Level 2 on Extreme (Tripmines page) / "Tripmines start spawning at level 3" (Extreme, Difficulty page — sources conflict; Casual: none). Kills on contact; explosion does not pierce shields; spawn rate/count scales with level — wiki. Extreme: explosion kills anyone in radius (Tripnuke innate) — wiki. Amount influenced by More Tripmines — wiki. Defuse Kit (3 stacks) and Subspacial Barrier can survive blasts — wiki.

### Flesh [wiki](https://nullscape.wiki/Flesh) [ofzen]
- Min level 5; max stack 2 — gamedata. Floats toward nearest player at 12 studs/second; phases through objects; non-fatal on touch — wiki.
- Passively infects nearby tiles (Light Flesh = slow; standing players get infected and spread it). Close proximity (red bubble) infects with Heavy Flesh: disables abilities and pauses Kolóna — wiki.
- Immunity 3 s after infection removed; ringing Bell cleanses nearby tiles and the ringer — wiki. From level 14: converts Light→Heavy flesh on contact (Extreme: default); level 28: increased infection range + longer durations — wiki/Progression_Events.
- ofzen: "infected tiles deal damage over time"; wet squelching sound; Spirit class tile-immunity counter; 1–2 s tier cues. (ofzen says DoT damage; wiki does not state damage numbers — no number given.)

### Baby [wiki](https://nullscape.wiki/Baby) [ofzen]
- Min level 1; max stack 2; 2 permanent Babies by level 10 adds Voidbound Baby — wiki/gamedata. Dashes in a straight line at nearest player; kills on touch even while not dashing — wiki.
- Targets nearest player; ~0.75 s dash-ready telegraph (dashed line), ~1 second dash along line, ~0.75 s idle before next dash — wiki. Extreme: dashes twice per attack, second trajectory set right after first — wiki.
- ofzen: small, fast, surprisingly high damage; high-pitched cry ~1 second before attack; cry = Priority 1 cue; Charger recommended. No numeric speed — no number given (faster than base walk speed — wiki).
- Counter: move out of the dash line; use elevation; 90° angles are most interceptable — wiki.

### Operator [wiki](https://nullscape.wiki/Operator) [ofzen]
- Min level 5; client-sided; only one at a time even on Extreme — wiki/gamedata (max stack 1, true max 1).
- Appears randomly as a green face with a ding; if player keeps any inputs (move/abilities), face turns yellow, then red (~right before 3 s), and a broken visor kills the player ~at 11 ticks — wiki. Kill check at ~11 ticks leaves 2.5 s to stop — wiki. Disappears promptly if no inputs within 3 seconds — wiki. Makes Voidbreaker/Kolóna wait (they alternate) — wiki.
- Voidbound Operator (Malfunction): first check on tick 15 or 21 (3.5 or 5 s) depending on movement, then 2 checks at 12-tick intervals, 2.5 s grace each — wiki.
- ofzen: fires spread-pattern projectiles; weapon charging sound ~2 s before volley; strafe perpendicular; Glider recommended. (ofzen's projectile description conflicts with wiki's stop-moving mechanic; wiki is authoritative. ofzen gives no projectile number.)
- No damage number — no number given (kills).

### Cadence [wiki](https://nullscape.wiki/Cadence) [ofzen]
- Min level 15; max stack 1 (hard limit even on Extreme; bypass via Trap Card/Level 50) — wiki/gamedata. Passive clock state cannot kill; spawns instruments near a player every 25 seconds (30 seconds if 2+ instruments uncollected); spawn rate scales with players alive (not starting count, per Nov 1 2026 change) — wiki.
- 2+ uncollected instruments decrease the enrage timer; otherwise timer increases. Solo timer starts and caps at 50 seconds — wiki.
- Timer expiry → enrage: breaks out, chases nearest at 80 studs/second (Extreme 130), kills on contact; instruments don't spawn while enraged; stops briefly after a kill — wiki. Extreme: 1 instrument present starts countdown — wiki.
- ofzen: instruments have distinct sounds — drums = radial shockwaves, strings = sweeping beams, wind = homing projectiles; attacks follow musical timing; Dancer/Spirit recommended. (ofzen's attack mapping conflicts with wiki's chase mechanic; wiki is authoritative.)
- Counter: collect instruments over gifts; watch the ticking; Radar Module: Instruments helps — wiki.

### Voidbreaker [wiki](https://nullscape.wiki/Voidbreaker) [ofzen]
- Min level 15; client-sided; max stack 2, true max 6; additional stacks increase appearance frequency, not swords — wiki/gamedata.
- Fades in around the player, lifts blade, summons sword(s) around the player; brief moment, then sword lunges to stab; must avoid blades by leaving sword direction — wiki. Swords cannot be dodged by jumping/falling — wiki.
- Casual: 1 sword/volley; Standard: 2 swords/volley; Extreme: extra volley, each volley fires 2 swords — wiki/gamedata.
- Spawn cooldown influenced by greater curses and by Operator/Scrapmaw and pause/extend curses — wiki. Swords behind the player can't hit if you keep moving forward — wiki.
- ofzen: telegraph = platform cracking? no — "platform cracking sound warns which platform will break" refers to Voidbreaker platform destruction; ofzen: "Voidbreaker breaks platforms and creates void zones"; Glider essential; Voidbreaker is listed as Level 15+. (ofzen's platform destruction is not in the wiki article; wiki is authoritative.)
- Client-sided, voidbound (only exclusively-voidbound enemy) — wiki.

Cross-source enemy count: ofzen says "18 entities … scrapmaw waiting at level 25" and groups them as early (level 1) / 5+ / 8+ / 10+ / 15+ / endgame; wiki's Scrapmaw entry: min level 25, "Blitzes toward the player, shooting beams", heavy mechanical grinding cue, ~30 s spawn (Casual ~40 s) — ofzen/Difficulty page. Neither gives a speed number for Scrapmaw [wiki](https://nullscape.wiki/Scrapmaw) [gamedata].

## 6. Core loop facts

### Objectives per level
- Every level: collect ALL Gifts to trigger "collapse" → opens the Beacon; Gold Gifts spawn where Gifts were — [Gifts](https://nullscape.wiki/Gifts), [Beacon](https://nullscape.wiki/Beacon).
- LAP 2 curse: Beacon instead needs 40% of Golden Gifts; opens automatically once every tile collapses — [LAP 2 data]/[Curses JSON].
- Encore curse: Beacon requires all Cadence instruments collected — [Encore data].
- Cadence instruments also gate her enrage — [Cadence].
- Gift count depends on max lobby player count, level number, and map-gen curses (e.g. Stairs… Stairs…) — [Gifts].
- Gift Arrow appears at 80% collected — [Gifts]. Each gift = 1 XP + 0.15 Tripcoins on successful finish — [Gifts][Tripcoins].
- Exception: Spirit cannot enter the Beacon in spirit form — [Beacon]. One person entering beats the level; others can then collect for Paycheck — [Beacon].

### Level size
- No absolute level-size number is given in any fetched source. Magnified Levels upgrade divides level size by 1.x per stack (min level 30) — [Upgrades JSON][Upgrades page]. Gift counts scale with lobby size and level — [Gifts].

### Exit / Beacon
- The Beacon is the exit; elevated on a platform at spawn; yellow-white neon beam; opens on collapse; only one player must enter — [Beacon].
- If all Pylons activate during collapse, Beacon turns pink — [Beacon spoiler].
- Beacon Mirage moves/replaces Beacon with random/fake ones inflicting Insanity — [Beacon][Curses].

### What happens on falling into the Void
- Below the map is the Void: invisible; touching it instantly kills, bypassing Shield; only escape = Void Shield from Altar of Protection + Drowned Ægis (one-time teleport out) — [Void].
- The Void's Y position is dynamic, based on map generation (since Patch 5) — [Void].

### Player health / lives
- No traditional health bar is described in the fetched sources; most hazards kill in one hit (Tripmines, Void, enemies), except Flesh (non-fatal) and Bell (not directly fatal on first touch).
- Shield upgrade grants one extra hit from most sources (not the Void) — [Upgrades]. Subspacial Barrier: extra Tripmine/Void Implosion hit — [Upgrades].
- Solo: one extra life, like Hope without the Golden Gift penalty; another in Casual/Standard every 25 levels; removed at Level 20 in Extreme if unused — [Lobby Sizes][Difficulty]. Breaking the last shield in Solo plays the Final Stand theme; Level 15+/30+ tracks — [Lobby Sizes].
- Cadence/Razorbloom/etc. kills tracked via statues; not relevant to lives.

### Voting between levels
- No fetched source mentions any voting mechanism between levels. (Inter-level intermissions exist: enemy/curse/upgrade shops appear in sequence — [Upgrades][Enemies][Curses].)

### What classes exist (as of Patch 5/5.1) [Classes](https://nullscape.wiki/Classes)
9 classes; 2 free (Charger, Diver — Diver is default), 3 in-shop (Spirit 1400 Tripcoins, Grappler 1800, Glider 2000), 2 achievement-gated (Prisoner = Level 25 [Extreme] badge; Wanted = Level 25 [Normal] badge), 2 dev/test-only jokes (Bruiser, phoon). Prisoner: no abilities, +25% Tripcoins, unaffected by non-speed upgrades, Kolóna never appears; Wanted: momentum-stop ability, stronger movement upgrades, +10% speed, some upgrades don't work.

### Intermission order (voting-adjacent facts)
- Enemy selection (on level 1 and even levels; every level on Extreme; 3 pedestals, re-rolls 2 base +1 per 5 levels) → Curse shop (even levels) → Upgrade shop (levels ending 0/3/5/8) → Greater Curses selection (levels 10/15/20+ depending on difficulty) — [Enemies][Curses][Upgrades][Difficulty].
- Enemy selection: pool based on level + permanent enemy counts; last chosen enemy unavailable next selection; Voidbound replaces regular in selections; Permanent enemies capped (doubled in Extreme); temporary enemies capped only for Operator/Kolóna/Cadence/Scrapmaw/Sigil/Voidbound ICBM/Catalyst — [Enemies].
- Progression events change the game every few levels (tripmines L5, Mart growth L6/12/…, ice tiles L8 (L5 Extreme), grindrails L10, seamines L10 (L15 Casual), Husk L10/25/50…, Flesh L14/L28, ICBM L16/32, highrise L18, Springer L20/40, curses every level L25 Standard, enemies every level L50) — [Progression_Events].
- Difficulty gates: Standard unlocked by level 15 on Casual+; Extreme unlocked by level 15 on Casual+ (page lists both) — [Difficulty]. Casual starts with Grace Wings + Miniature Hourglass, no Tripmines, 0.8x Tripcoins; Extreme: 1.5x Tripcoins, earlier progression events, faster AI — [Difficulty].
