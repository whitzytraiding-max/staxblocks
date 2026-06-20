# STAX — Handoff for the next session (2026-06-20)

Hey future Claude. Jay (CEO, the user) and I did a big multi-session run. Everything below is
**pushed to `origin/main`** (`github.com/XSideZ/stax-game`, HEAD `1eb6fb4`). You CAN `git push origin
main` from this clone. Jay's friend builds the **iOS** app from `main` (now a **Godot 4.7** project).

## ⚠️ Read this first
- **You CANNOT test on PC the way it matters.** The account/restore flow needs the iOS OAuth round-trip;
  the skins and battery/perf only show on the phone (esp. the 120 Hz iPhone 16 Pro). So skin/feel work
  is **blind iteration**: make tasteful changes → Jay builds & tests → he reports → you adjust.
- **Don't run Godot headless to "verify"** unless you really need to — the project is on 4.7 and churning
  `.godot`/`project.godot` under a mismatched local engine has burned us. The edits are simple GDScript;
  eyeball them instead.
- **Load-bearing (don't break):** never reorder fields in `GameState._save`/`_read_save_fields` (append
  only); keep the crash-safe save (atomic temp+rename, `.bak`, never wipe on short read); center banners
  go through the queue (don't call `_spawn_*` directly).

## 🎨 THE 4 SKINS — this is the active task Jay wants continued
All skin renderers live in **`scripts/BlockSkins.gd`** as `static func _name(...)`, dispatched by style
index in `paint()`. The biome/skin list and names live in 3 other files (see "renaming a skin" below).

**Why these 4 were a problem:** the originals did **dozens of `clip_poly_to_rect` calls per cell** to
paint continuous patterns across the board → big framerate drops (Jay's complaint). I rewrote them.

**THE PERFORMANCE RULE (do not violate):** cheap renderers only — a gradient (`rr_grad`) + a small
number of **in-bounds** primitives (`ci.draw_circle`, `ci.draw_line`, `ci.draw_polyline`,
`draw_poly_safe(ci, pts, col, true)` for convex polys). **NO `clip_poly_to_rect`. NO per-cell loops over
board space.** The gold-standard cheap template is **`_synthwave`** (style 27) — study it.

Helpers: `rr_fill(ci,rect,rad,col)`, `rr_grad(ci,rect,rad,top,bot)`, `rr_outline(ci,rect,rad,col,w)`,
`draw_poly_safe(ci,pts,col,assume_convex)`. Each skin maps the piece `col` to its palette so pieces stay
tellable apart.

**Current state of the 4 (after "skin pass 2", commit `1eb6fb4`):**
| Style | Name   | Func       | Anim? | What it draws now |
|-------|--------|------------|-------|-------------------|
| 12    | HONEY  | `_honey`   | static | gradient + full 7-cell honeycomb + honey pool + sheen + bubbles |
| 20    | AURORA | `_aurora`  | **animated** | night gradient + 3 wavy curtain bands (polylines, ripple/drift/hue-shift) + twinkling stars |
| 22    | OPAL   | `_opal`    | **animated** | NEW skin (replaced MARBLE) — milky base + drifting iridescent colour flecks + breathing glow + sparkles |
| 26    | STAINED| `_stained` | static | 5-pane leaded window (centre diamond + 4 corner panes, varied hues, lead came + bevels) |

The **`ANIMATED`** const (top of BlockSkins.gd, ~line 15) lists styles that force per-frame redraws.
honey(12)+stained(26) are NOT in it (static); aurora(20)+opal(22) ARE (cheap legendary shimmer).
**Jay said aurora & opal are "legendary" tier → they should stay animated.** sakura(16)/autumn(28) were
already fine — don't touch them.

**Jay's latest feedback (the to-do):** he picked **Opal** to replace marble. He'll test pass-2 and tell
you what's still off (e.g. "opal more/less colourful", "aurora bands bigger/wavier", "honey/stained still
missing something"). Iterate on the LOOK while keeping the performance rule.

**Renaming a skin touches 4 places** (I did marble→opal across all of them — follow this if renaming):
1. `BlockSkins.gd` — the `_name` renderer + the `NN: _name(...)` dispatch line in `paint()`.
2. `MainMenu.gd` — `SKIN_NAMES` array (~line 44).
3. `GameState.gd` — the `THEMES` biome entry (~line 521): `{bg, orb, accent, name}`.
4. `Game.gd` — `_draw_bg_pattern()` match, the `NN:` case (the board background for that biome).

## ✅ Everything else done across these sessions (all on `main`)
- **Branding/logo:** new STAX logo = chunky 3D candy lettering. App icon = stacked **ST/AX on a neon-glow
  bg**; full iOS PNG set + sources at `C:\Users\johal\Desktop\STAX-logo-concepts\` (generator `_gen.py`,
  rasterised via headless Chrome). In-game **falling menu letters restyled** to match (`MainMenu._build_logo`
  + `LOGO_COLORS`). Pick still pending for final iOS-icon swap on Jay's side.
- **Account / restore UX:** returning players no longer re-prompted for a name (`MainMenu._ready` guard);
  restore brings back the real account name (`GameState.apply_cloud_profile(d, restoring)`); leaderboard/
  biomes **lock state refreshes after a restore** (`_refresh_menu_buttons`); **overlay panels always raise
  to front on open** (`ui.move_child(box,-1)` in every `_open_*`) — fixed "menus open behind the buttons".
- **Difficulty:** cranked hard (`4314056`) then **eased one notch** (`cd8eb86`). Knobs are named consts in
  `Game.gd` + `_hard_bias()`/`_pick_adversarial_shape()`. **Jay is still dialing it in** — he may ask for
  another small ease ("a tiny bit more") or say it's perfect.
- **Perf/battery:** `Engine.max_fps = 60` (GameState._ready) + `application/run/max_fps=60` — the iPhone 16
  Pro was rendering at 120 Hz. Plus the skin-lag fix above. If still hot, next lever = throttle the menu's
  `queue_redraw`/`faller_layer.queue_redraw` to ~30fps.
- **Leaderboard:** shows **top 1000** now (client `fetch_global(1000)` + the `get_global_board` RPC cap
  raised 200→1000 — **Jay already ran the SQL** in Supabase).
- **Menu freeze on spam-tap:** re-entry guards `_launching` / `_confirm_open` in MainMenu (launch + new-game
  confirm + the name-prompt LET'S GO).
- **Double bomb:** now spends the WHOLE meter; the two bombs land **≥3 cells apart** (`_far_target`).
- **`project.godot`:** moved to **Godot 4.7** (`config/features`) — friend updating to 4.7.

## How Jay likes to work (from memory)
- Just build it; don't present a wall of options. Push after a fix lands (he tests on phone). Give SQL as
  clean copy-paste blocks (he runs SQL/deploys himself). Don't ask "want me to ship?". Proactively ask him
  to run device probes you can't do yourself. He has a proven short-form viral skill — launches are organic.

Good luck. Pick up the skins. — Claude (2026-06-20)
