# PARKED.md — every parked ticket and every parked rule

A row here is a written reason: what failed, the output, what was tried. A ticket is never dropped
silently (FLEET_PACK.md §10.1 R1). A contradiction a worker finds is parked here and the orchestrator
does not resolve it either (R5).

| # | ticket | what was parked | why | what was tried |
|---|---|---|---|---|
| 1 | T-027 | ENEMIES.md contradicts itself on which side enemy LOGIC runs. Intro: "Like Nullscape, all enemies are client-sided - rendered on the client, not the server." Global notes: "All enemies stay server-sided (Nullscape's enemies are all server-sided too) - apart from gin ichimaru and his spears (spears included): rendered on the client, never the server." | The two passages say opposite things about the logic side. DESIGN.md §5 and the T-027 spec text both follow the global notes, so the intro is the outlier. Neither passage was edited. | Built the global-notes reading: enemy logic in `sim/enemy_runtime.gd` (server-sided); all sprites, billboarding and spawn text in the view layer (client-side). This satisfies the intro for everything the intro names (rendering) and the global notes for logic. Owner to rule which passage stands. |
