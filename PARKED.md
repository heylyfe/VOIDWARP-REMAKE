# PARKED.md - spec conflicts found while building, parked for the owner

A row here means: this ticket read the two conflicting passages, built the reading closest to
ENEMIES.md, did NOT resolve or rewrite either passage, and continues on the built reading until
the owner rules.

| ticket | the two conflicting passages | what was built meanwhile |
|---|---|---|
| T-027 | ENEMIES.md intro: "Like Nullscape, all enemies are client-sided - rendered on the client, not the server." vs ENEMIES.md "Global notes": "All enemies stay server-sided (Nullscape's enemies are all server-sided too) - apart from gin ichimaru and his spears (spears included): rendered on the client, never the server." DESIGN.md section 5 follows the global notes ("Enemy logic runs in the deterministic simulation (the future server). Sprites, billboarding and gin ichimaru's spears are view-layer only."), and FLEET_PACK T-027 also quotes the global-notes sentence. The two passages say opposite things about the LOGIC side (client vs server). | Enemy logic in `sim/enemy_runtime.gd` (server-sided, per the global notes + DESIGN section 5 + the T-027 spec text); all sprites, billboarding and spawn text in the view layer, client-side. This is the global-notes reading and it is also the client-intro reading for everything the intro names (rendering); nothing was written into ENEMIES.md. |
