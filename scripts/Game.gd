extends Node2D

# ── Piece shapes ──────────────────────────────────────────────────────────────
const SHAPES: Array = [
	[[0,0]],
	[[0,0],[1,0]],
	[[0,0],[0,1]],
	[[0,0],[1,0],[2,0]],
	[[0,0],[0,1],[0,2]],
	[[0,0],[1,0],[2,0],[3,0]],
	[[0,0],[0,1],[0,2],[0,3]],
	[[0,0],[1,0],[2,0],[3,0],[4,0]],
	[[0,0],[0,1],[0,2],[0,3],[0,4]],
	[[0,0],[1,0],[0,1],[1,1]],
	[[0,0],[1,0],[2,0],[0,1],[1,1],[2,1],[0,2],[1,2],[2,2]],
	[[0,0],[1,0],[0,1]],
	[[0,0],[1,0],[1,1]],
	[[0,0],[0,1],[1,1]],
	[[1,0],[0,1],[1,1]],
	[[0,0],[0,1],[0,2],[1,2]],
	[[1,0],[1,1],[0,2],[1,2]],
	[[0,0],[1,0],[2,0],[1,1]],
	[[0,0],[1,0],[2,0],[0,1]],
	[[0,0],[1,0],[2,0],[2,1]],
	[[0,0],[1,0],[1,1],[1,2]],
	[[0,0],[1,0],[0,1],[0,2]],
	# S / Z tetrominoes (horizontal + vertical)
	[[1,0],[2,0],[0,1],[1,1]],
	[[0,0],[1,0],[1,1],[2,1]],
	[[0,0],[0,1],[1,1],[1,2]],
	[[1,0],[0,1],[1,1],[0,2]],
	# T rotations (up / left / right — down already exists)
	[[1,0],[0,1],[1,1],[2,1]],
	[[0,0],[0,1],[1,1],[0,2]],
	[[1,0],[0,1],[1,1],[1,2]],
	# Plus / cross
	[[1,0],[0,1],[1,1],[2,1],[1,2]],
	# Filled 2×3 and 3×2 rectangles
	[[0,0],[1,0],[2,0],[0,1],[1,1],[2,1]],
	[[0,0],[1,0],[0,1],[1,1],[0,2],[1,2]],
	# Diagonals (2- and 3-cell, both directions) — tricky, show up more late-game
	[[0,0],[1,1]],
	[[1,0],[0,1]],
	[[0,0],[1,1],[2,2]],
	[[2,0],[1,1],[0,2]],
	# Big corner "L" — two 3-long arms sharing a corner (5 cells), all 4 rotations
	[[0,0],[0,1],[0,2],[1,2],[2,2]],
	[[0,0],[1,0],[2,0],[0,1],[0,2]],
	[[0,0],[1,0],[2,0],[2,1],[2,2]],
	[[2,0],[2,1],[0,2],[1,2],[2,2]],
]

const COLORS: Array = [
	Color(0.32, 0.80, 0.97),
	Color(1.00, 0.63, 0.28),
	Color(0.95, 0.36, 0.68),
	Color(0.33, 0.90, 0.55),
	Color(0.73, 0.43, 0.97),
	Color(0.97, 0.88, 0.32),
]

# ── Themes ────────────────────────────────────────────────────────────────────
# Theme data lives in GameState.THEMES (shared with the menus so their
# backgrounds follow the selected skin). Alias keeps local references short.
# Style/theme index: 0=Pastel 1=Neon 2=Circuit 3=BrickWall 4=Crystal 5=Candy
#                    6=Frost 7=Grass 8=Water 9=Lava 10=Wood 11=Galaxy
var THEMES : Array = GameState.THEMES
const THEME_INTERVAL := 7

# ── Scoring ───────────────────────────────────────────────────────────────────
# Modeled on Block Blast's economy: cleared cells are the currency (10/cell),
# simultaneous multi-line clears earn a NON-linear bonus, back-to-back clear
# streaks multiply clear points only (capped), and a full-board clear is a
# flat cherry worth ~4 single lines — never the dominant strategy.
const CELL_POINTS     := 10
const MULTI_BONUS     : Array = [0, 0, 40, 90, 180, 300, 450]   # index = lines cleared (6+ capped)
const STREAK_STEP     := 0.30     # +30% clear points per consecutive clearing move
const STREAK_CAP      := 6.0      # streak multiplier ceiling
const BOARD_CLEAR_PTS := 400
# Depth scaling: surviving deep into a run makes every move worth more —
# +5% per placement, capping at x12 (220 moves in). Tuned so a strong
# 10-15 minute run (~150-200 moves with steady clears) reaches ~100k.
const DEPTH_STEP      := 0.05
const DEPTH_CAP       := 12.0

# ── Layout ────────────────────────────────────────────────────────────────────
const GRID_X    := 24.0
const GRID_Y    := 175.0
const CELL      := 44.0
const GRID_STEP := 46.0
const GRID_COLS := 8
const GRID_ROWS := 8

const TRAY_Y    := 600.0
const TRAY_H    := 175.0
const TRAY_CELL := 28.0
const TRAY_STEP := 29.0
const SLOT_W    := 138.0

# Dragged pieces float this far above the touch point so the finger
# doesn't cover them
const DRAG_LIFT := 70.0

# How far (in cells) the snap will reach for the nearest valid spot when the
# touch isn't dead-on — bigger = more forgiving for fast play. The ghost shows
# exactly where it lands, so over-reach stays visible before releasing.
const SNAP_REACH := 4

# Hysteresis (in cells) for snap placement: once locked, the piece HOLDS its cell
# until the finger pushes this far past the half-cell switch point — symmetric on
# every side, so it stops flipping on a 1-2px nudge. Higher = stickier lock.
const SNAP_HYST := 0.25
var snap_anchor := Vector2i(-999, -999)   # last locked PLACEMENT cell (drag hysteresis)

# ── Power meter ───────────────────────────────────────────────────────────────
# One charge bar fills from clears. Spend it (tap the orb) on the best ability
# it can afford: ¼ Bomb, ½ Laser, FULL Gravity Slam (the ultimate).
const METER_BOMB     := 0.25
const METER_LASER    := 0.50
const METER_FULL     := 1.0
const METER_PER_LINE := 0.06    # charge gained per line cleared
const POWER_CENTER   := Vector2(50.0, 70.0)
const POWER_R        := 30.0

const EARLY_SHAPES: Array = [
	[[0,0]],
	[[0,0],[1,0]],
	[[0,0],[0,1]],
	[[0,0],[1,0],[2,0]],
	[[0,0],[0,1],[0,2]],
	[[0,0],[1,0],[0,1]],
	[[0,0],[1,0],[1,1]],
	[[0,0],[0,1],[1,1]],
	[[1,0],[0,1],[1,1]],
	[[0,0],[1,0],[0,1],[1,1]],
]

# ── State ─────────────────────────────────────────────────────────────────────
var pieces        : Array   = []
var placed        : Array   = [false, false, false]
var dragging_slot : int     = -1
var drag_pos      : Vector2 = Vector2.ZERO
var score         : int     = 0
var sets_given    : int     = 0
var lines_cleared : int     = 0
var combo         : int     = 0
var placements    : int     = 0      # pieces placed this run — drives smart spawning
var run_over      : bool    = false  # blocks auto-save once the run has ended
var max_combo     : int     = 0      # best streak this run (game-over breakdown)
var board_clears  : int     = 0      # full-board clears this run
var sets_since_clear : int = 0       # sets since the last board clear → drives the drain
var streak_lost_t : float   = 0.0    # drives the "streak lost" flash on the meter
var drag_pop_t    : float   = 0.0    # pickup swell on the dragged piece

# Power meter state
var meter       : float = 0.0     # charge 0..1
var power_busy  : bool  = false   # an ability animation is playing
var power_pulse : float = 0.0     # orb flash right after firing
var _icon_font : Font = load("res://assets/fonts/baloo2_semibold.tres")  # for the "×2" power-icon label
var last_power_tier : int = 0     # detect crossing into a new ability tier
var fx_layer    : Node2D          # top layer for bomb/laser/gravity effects
var effects     : Array = []      # active visual effects
var praise_pops : Array = []      # active rainbow per-letter praise popups (NICE!, etc.)
# Center-banner queue: line-clear praise, BOARD CLEAR, biome name all share the same
# center strip, so they're shown one-after-another (a quick cascade) instead of mashing
# on top of each other. Drained in _process so nothing fires after a scene change.
var banner_queue : Array = []     # [{fn: Callable, slot: float}, …]
var _banner_t    : float = 0.0    # time left before the center strip is free for the next

# Drag-hover haptic: buzz once each time we move onto a new valid placement
var last_hover_snap  : Vector2i = Vector2i(-99, -99)
var last_hover_valid : bool     = false

# Score count-up: the label chases the real score so it flies up instead of jumping
var disp_score : float = 0.0

# Theme / background
var theme_idx     : int    = 0
var prev_bg       : Color  = THEMES[0]["bg"]
var curr_bg       : Color  = THEMES[0]["bg"]
var theme_lerp    : float  = 1.0

# Screen shake
var shake_t      : float   = 0.0
var shake_offset : Vector2 = Vector2.ZERO

# Transition flash
var flash_t   : float = 0.0
var flash_col : Color = Color.TRANSPARENT

# Animated orbs
const ORB_COUNT := 14
var orbs: Array = []
var orb_boost : float = 0.0   # transient speed whoosh on biome change, decays in _process

# Pause / settings overlay
const GEAR_RECT := Rect2(360.0, 26.0, 42.0, 42.0)
var menu_open  : bool = false
var pause_menu : Control

# First-run tutorial coach (null unless GameState.tutorial_active). While present
# it suspends auto-save and forwards placement/power events to the coach.
var tutorial : Node = null
# Guided-placement lock: during the coached steps only this slot may be grabbed,
# and it always lands on this cell (magnetised) so the player can't misplace it.
var tut_lock_slot : int     = -1
var tut_lock_cell : Vector2i = Vector2i.ZERO

# Power rescue: when no piece fits but a charged ability could clear space, give
# the player a few seconds + a prompt to fire it instead of instantly losing.
const RESCUE_SECS := 4.5
var rescue_active   : bool  = false
var rescue_timer    : float = 0.0
var _was_rescue     : bool  = false   # detect the rescue prompt ending (repaint to clear it)
var _was_power_busy : bool  = false   # detect when a fired power finishes resolving

# Idle background redraws throttle to ~30fps (perf: the parallax skins are the
# heavy per-frame cost on mobile). Any gameplay action redraws at full 60fps.
var _idle_redraw_accum : float = 0.0
# Reused colour buffer for the UI _rr_grad helper — avoids a per-call alloc.
var _ui_gradbuf : PackedColorArray = PackedColorArray()
# The drag overlay only needs redrawing while a piece is held; track so we can
# stop pumping it a redraw every idle frame (and clear it once on drop).
var _drag_layer_active : bool = false

# Tray spawn bounce
var tray_pop_t : float = 0.0
var score_glow : float = 0.0   # 0..1 rainbow intensity, ramps with score (half@50k, full@100k)

@onready var grid        : Grid        = $Grid
@onready var score_label : Label       = $UI/ScoreLabel
@onready var best_label  : Label       = $UI/BestLabel
@onready var combo_label : Label       = $UI/ComboLabel
@onready var ui          : CanvasLayer = $UI

# Overlay for the dragged piece — added after Grid so it renders ON TOP of
# the board (it used to draw under the grid blocks)
var drag_layer : Node2D

func _ready() -> void:
	# Keep whatever skin was last in play: a continued run restores its theme,
	# and a fresh run inherits the skin from the run that just ended (no jarring
	# re-randomize on death). It still rotates during play on line milestones.
	theme_idx = GameState.theme_idx % THEMES.size()
	if not GameState.has_save:
		GameState.set_theme(theme_idx)
	curr_bg   = THEMES[_visual_idx()]["bg"]
	prev_bg   = curr_bg
	_init_orbs()
	_build_pause_menu()
	drag_layer = Node2D.new()
	# Above the board's animated frame (Grid frame_rect), so a lifted piece
	# floats over the border instead of being clipped under it.
	drag_layer.z_index = 2
	add_child(drag_layer)
	drag_layer.draw.connect(_draw_drag_layer)
	# Effects layer sits on top of everything (explosions, beams, slam streaks)
	fx_layer = Node2D.new()
	fx_layer.z_index = 3
	add_child(fx_layer)
	fx_layer.draw.connect(_draw_fx_layer)
	# Score bounce should swell from the badge centre, not the corner
	score_label.pivot_offset = score_label.size * 0.5
	combo_label.pivot_offset = combo_label.size * 0.5
	_apply_block_style()
	if GameState.has_save:
		_restore_state()
		GameState.has_save = false
		if GameState.continue_mode == "ad":
			GameState.revive_used = true   # one revive per run
			GameState.add_revive()
	else:
		GameState.revive_used = false
		_spawn_pieces()
	_refresh_best()
	Sfx.update_music()
	if GameState.tutorial_active:
		_start_tutorial()

# ── Orbs ──────────────────────────────────────────────────────────────────────
func _init_orbs() -> void:
	orbs = []
	for _i in ORB_COUNT:
		orbs.append(_make_orb())

func _make_orb() -> Dictionary:
	var orb_col: Color = THEMES[_visual_idx()]["orb"]
	return {
		"pos":    Vector2(randf() * 414.0, randf() * 896.0),
		"vel":    Vector2((randf() - 0.5) * 22.0, (randf() - 0.5) * 22.0),
		"radius": randf_range(50.0, 130.0),
		"color":  Color(orb_col.r, orb_col.g, orb_col.b, randf_range(0.04, 0.11)),
	}

func _update_orbs(delta: float) -> void:
	var spd := 1.0 + orb_boost
	for orb in orbs:
		orb["pos"] += orb["vel"] * delta * spd
		if orb["pos"].x < -140.0 or orb["pos"].x > 554.0:
			orb["vel"].x = -orb["vel"].x
		if orb["pos"].y < -140.0 or orb["pos"].y > 1036.0:
			orb["vel"].y = -orb["vel"].y

# ── Process ───────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_update_orbs(delta)
	if orb_boost > 0.0:
		orb_boost = maxf(0.0, orb_boost - delta * 1.4)

	if theme_lerp < 1.0:
		theme_lerp = minf(theme_lerp + delta / 1.5, 1.0)

	if shake_t > 0.0:
		shake_t = maxf(shake_t - delta, 0.0)
		var intensity := shake_t * shake_t * 20.0
		shake_offset = Vector2(
			sin(shake_t * 53.0) * intensity,
			cos(shake_t * 41.0) * intensity * 0.6
		)
		grid.position = Vector2(GRID_X, GRID_Y) + shake_offset
	else:
		shake_offset = Vector2.ZERO
		grid.position = Vector2(GRID_X, GRID_Y)

	if flash_t > 0.0:
		flash_t = maxf(flash_t - delta / 0.35, 0.0)

	if tray_pop_t > 0.0:
		tray_pop_t = maxf(tray_pop_t - delta * 2.5, 0.0)

	if streak_lost_t > 0.0:
		streak_lost_t = maxf(streak_lost_t - delta / 1.1, 0.0)
		if streak_lost_t == 0.0:
			_update_combo_label()

	if drag_pop_t > 0.0:
		drag_pop_t = maxf(drag_pop_t - delta * 4.0, 0.0)

	# Power visual effects advance + cull
	if not effects.is_empty():
		var alive : Array = []
		for e in effects:
			e["t"] += delta
			if e["t"] < e["dur"]:
				alive.append(e)
		effects = alive
		fx_layer.queue_redraw()
	# Moving-rainbow praise letters (NICE!, BOARD CLEAR!, …)
	_animate_praise(delta)
	_drain_banner_queue(delta)
	# The rescue prompt lives on fx_layer and animates (pulse + countdown), so keep it
	# repainting while active — and once more when it ends so the banner clears.
	if rescue_active or _was_rescue:
		fx_layer.queue_redraw()
	_was_rescue = rescue_active
	if power_pulse > 0.0:
		power_pulse = maxf(power_pulse - delta * 2.0, 0.0)

	# Crossing into a new ability tier flashes the orb to draw the eye
	var tier := _power_tier()
	if tier > last_power_tier:
		power_pulse = 1.0
		Sfx.play_tick()
		_buzz(10 + tier * 6)
	last_power_tier = tier

	# Score count-up: the displayed number flies toward the real score
	if disp_score != float(score):
		disp_score = lerpf(disp_score, float(score), clampf(delta * 14.0, 0.0, 1.0))
		if absf(float(score) - disp_score) < 1.0:
			disp_score = float(score)
		_set_score_text(int(round(disp_score)))

	# Score "powers up" into a glowing rainbow as it climbs — ~half tint at 50k,
	# fully rainbow + glowing by 100k. score_glow also drives the halo in _draw.
	score_glow = clampf(float(score) / 100000.0, 0.0, 1.0)
	if score_glow > 0.0:
		score_label.modulate = Color.WHITE.lerp(_score_shimmer_color(), score_glow)
	else:
		score_label.modulate = Color.WHITE

	# When a fired power finishes, resolve survival (a spent power never kills you)
	if _was_power_busy and not power_busy:
		_resolve_after_power()
	_was_power_busy = power_busy

	# Rescue countdown — only while waiting for the player to act on the prompt
	if rescue_active and not power_busy:
		rescue_timer -= delta
		if rescue_timer <= 0.0:
			_game_over()

	# Full-rate redraw during any motion; throttle the idle parallax to ~30fps
	var busy : bool = shake_t > 0.0 or flash_t > 0.0 or power_pulse > 0.0 \
		or theme_lerp < 1.0 or tray_pop_t > 0.0 or streak_lost_t > 0.0 \
		or drag_pop_t > 0.0 or dragging_slot >= 0 or rescue_active \
		or not effects.is_empty() or disp_score != float(score)
	if busy:
		queue_redraw()
	else:
		_idle_redraw_accum += delta
		if _idle_redraw_accum >= 1.0 / 30.0:
			_idle_redraw_accum = 0.0
			queue_redraw()
	# Only pump the drag overlay while a piece is actually held. On release we
	# redraw once more to clear it, then leave it idle (was redrawing 60×/sec
	# every frame even with nothing to draw).
	if dragging_slot >= 0:
		drag_layer.queue_redraw()
		_drag_layer_active = true
	elif _drag_layer_active:
		drag_layer.queue_redraw()
		_drag_layer_active = false

# ── Spawning ──────────────────────────────────────────────────────────────────
func _spawn_pieces() -> void:
	pieces        = []
	placed        = [false, false, false]
	dragging_slot = -1

	# Slot 0 is gifted a board-clearing piece when one exists — but only some of the
	# time once the run gets going. Early on it's near-guaranteed (keeps the fast
	# board-clear loop); deep in a run it's rare, so survival gets real.
	# Slot 0 is gifted a board-clearing piece. The opening keeps the satisfying near-
	# guaranteed loop; once past it the gift tapers from ~70% down to rare, so from
	# ~10k upward the board stops being constantly emptied for you.
	var forced_clear : Array = []
	var gift_chance : float = 1.0 if sets_given < EARLY_CLEAR_SETS \
		else lerpf(0.20, 0.0, _difficulty())
	if randf() < gift_chance:
		forced_clear = _pick_board_clear_shape()

	var picked_keys: Array = []
	for _i in 3:
		var shape : Array = forced_clear if (_i == 0 and not forced_clear.is_empty()) else _pick_shape()
		var key   := str(shape)
		# Never give three identical shapes — when blocked, pick from EARLY_SHAPES
		# excluding the duplicate. Don't re-call _pick_shape() which may always
		# return the same thing when the board has only one matching gap pattern.
		if picked_keys.size() == 2 and picked_keys[0] == picked_keys[1] and key == picked_keys[0]:
			var blocked : String = picked_keys[0]
			var alts: Array = []
			for s in EARLY_SHAPES:
				if str(s) != blocked:
					alts.append(s)
			if alts.is_empty():
				for s in SHAPES:
					if str(s) != blocked:
						alts.append(s)
			if not alts.is_empty():
				shape = alts[randi() % alts.size()]
				key   = str(shape)
		picked_keys.append(key)
		# "pattern" = random crop position in the virtual skin canvas — makes
		# every piece's skin detail unique (cells of one piece stay related)
		pieces.append({"shape": shape, "color": COLORS[randi() % COLORS.size()],
			"pattern": randi() % 1000000})

	sets_given += 1
	sets_since_clear += 1
	tray_pop_t = 1.0
	grid.clear_ghost()
	queue_redraw()
	if not grid.can_any_fit(_shapes_array(), placed):
		_try_game_over()

func _progression() -> float:
	return clampf((sets_given - 1) / 3.0, 0.0, 1.0)

# Run difficulty 0..1. Stays 0 through the (already well-tuned) early game, then
# ramps up so the generosity crutches fade and it gets genuinely hard. Driven by the
# MAX of two ramps — sets played AND score — so a fast high-scoring run gets hard on
# schedule (the 50-100k window was way too easy when difficulty tracked sets alone).
const DIFF_START := 2.0        # sets before the sets-ramp starts climbing (= early phase)
const DIFF_LEN   := 14.0       # sets over which the sets-ramp climbs to max (bites fast)
const DIFF_SCORE_START := 1000.0   # score where the score-ramp begins (bites very early)
const DIFF_SCORE_LEN   := 11000.0  # score span to max (~12k → fully hard)
func _difficulty() -> float:
	var by_sets  := (float(sets_given) - DIFF_START) / DIFF_LEN
	var by_score := (float(score) - DIFF_SCORE_START) / DIFF_SCORE_LEN
	return clampf(maxf(by_sets, by_score), 0.0, 1.0)

# Deep-run pressure that keeps climbing AFTER _difficulty() has maxed (score 80k→300k),
# so a long high-score run keeps tightening instead of plateauing at "max" difficulty.
const DEEP_START := 20000.0
const DEEP_LEN   := 130000.0
func _deep() -> float:
	return clampf((float(score) - DEEP_START) / DEEP_LEN, 0.0, 1.0)

# How often the spawner deliberately hands a crowding, hard-to-place piece instead of
# a helpful one. Climbs with both ramps so a long high-score run keeps getting meaner;
# capped below 1.0 so there's always a sliver of breathing room (and the rescue power).
func _hard_bias() -> float:
	return clampf(lerpf(0.0, 0.54, _difficulty()) + lerpf(0.0, 0.22, _deep()), 0.0, 0.72)

# The meanest fitting piece: the more cells it has and the FEWER places it fits, the
# more it crowds the board and strands gaps. Small random jitter keeps it from handing
# the exact same shape every time. Returns [] only if nothing fits at all.
func _pick_adversarial_shape() -> Array:
	var any_fit  : Array = []
	var best     : Array = []
	var best_rank : float = INF
	for s in SHAPES:
		var fit_count := 0
		for r in GRID_ROWS:
			for c in GRID_COLS:
				if grid.can_place(s, r, c):
					fit_count += 1
		if fit_count == 0:
			continue
		any_fit.append(s)
		# Lower rank = meaner: few placements, many cells. Jitter breaks ties softly.
		var rank := float(fit_count) - float(s.size()) * 2.5 + randf() * 1.5
		if rank < best_rank:
			best_rank = rank
			best = s
	if not best.is_empty():
		return best
	if not any_fit.is_empty():
		return any_fit[randi() % any_fit.size()]
	return []

# Drain toward a board clear: early in the run, or when it's been too long since
# the last one. The drought threshold GROWS with difficulty so board-clear bailouts
# get rarer the deeper you are — the board stays fuller and the pressure builds.
func _wants_clear() -> bool:
	# Board-clear bailouts get rarer as the run gets harder: drought grows with
	# difficulty, then keeps growing into the deep game so the board stays full and
	# the pressure is real at high scores.
	var drought : int = int(round(
		lerpf(float(CLEAR_DROUGHT), 60.0, _difficulty()) + lerpf(0.0, 32.0, _deep())))
	return sets_given < EARLY_CLEAR_SETS or sets_since_clear >= drought

# Fraction of the board currently filled (0..1).
func _board_fill() -> float:
	var n := 0
	for r in GRID_ROWS:
		for c in GRID_COLS:
			if grid.cells[r][c] != null:
				n += 1
	return float(n) / float(GRID_ROWS * GRID_COLS)

# Filler pool that adapts to coverage: roomy board → lean to big clean blocks (a
# MIX, not a spam); as it fills, shift to smaller pieces so big blocks never clog.
# Big blocks still come from board-clear gifts and line-completers, so no shape is
# ever fully removed — they just taper as the board gets covered.
func _fill_pool() -> Array:
	var ratio := _board_fill()
	if ratio < 0.30:
		return CLEAN_SHAPES if randf() < 0.55 else EARLY_SHAPES
	elif ratio < 0.52:
		return CLEAN_SHAPES if randf() < 0.28 else EARLY_SHAPES
	return EARLY_SHAPES

# Early-game generosity fades GRADUALLY: 85% smart picks at move 0, easing
# to 0% by move ~45. Smart picks complete lines (multi-line wins outright);
# when nothing clears yet, hand out big "builder" pieces so the board fills
# fast and double/triple clears set themselves up.
const SMART_FADE_MOVES := 10.0

# Early game = a fast "clear the whole board" puzzle. For the first few sets we
# keep the board SMALL (no big builder dumps) and try to hand the player a piece
# that can empty the board, so full board-clears happen constantly up front.
const EARLY_CLEAR_SETS   := 3
const EARLY_CLEAR_CHANCE := 1.0
# After this many sets with no full board clear, briefly favour small clearing
# pieces again (a "drain") to set up another board clear — keeps board clears
# frequent across long runs, not just at the start.
const CLEAR_DROUGHT := 5

const BUILDER_SHAPES : Array = [
	[[0,0],[1,0],[2,0],[3,0]],
	[[0,0],[0,1],[0,2],[0,3]],
	[[0,0],[1,0],[2,0],[3,0],[4,0]],
	[[0,0],[0,1],[0,2],[0,3],[0,4]],
	[[0,0],[1,0],[0,1],[1,1]],
	[[0,0],[1,0],[2,0],[0,1],[1,1],[2,1]],
	[[0,0],[1,0],[0,1],[1,1],[0,2],[1,2]],
	[[0,0],[1,0],[2,0],[0,1],[1,1],[2,1],[0,2],[1,2],[2,2]],
]

# Clean rectangular tiles for the opening / drain: they pack the board EVENLY and
# clear in big chunks (Block-Blast style). Weighted toward 3x3 and 2x3/3x2 — they
# score big and set up easy board clears, and never leave a stray block the way
# L/odd shapes do. Duplicates raise the odds of the bigger tiles.
const CLEAN_SHAPES : Array = [
	[[0,0],[1,0],[2,0],[0,1],[1,1],[2,1],[0,2],[1,2],[2,2]],  # 3x3
	[[0,0],[1,0],[2,0],[0,1],[1,1],[2,1],[0,2],[1,2],[2,2]],  # 3x3
	[[0,0],[1,0],[2,0],[0,1],[1,1],[2,1]],                     # 3x2
	[[0,0],[1,0],[2,0],[0,1],[1,1],[2,1]],                     # 3x2
	[[0,0],[1,0],[0,1],[1,1],[0,2],[1,2]],                     # 2x3
	[[0,0],[1,0],[0,1],[1,1],[0,2],[1,2]],                     # 2x3
	[[0,0],[1,0],[0,1],[1,1]],                                 # 2x2
]

func _pick_shape() -> Array:
	# DRAIN MODE (early game, or a board-clear drought): ONLY small pieces, strongly
	# biased to completing lines, so the board drains toward a full clear.
	if _wants_clear():
		# Helpful mix that ADAPTS to how full the board is: gift a one-piece board
		# clear if possible, else a shape that completes a line, else a filler whose
		# size scales with free space — bigger clean blocks while there's room, then
		# smaller pieces as coverage rises so big blocks never clog the board.
		var bc := _pick_board_clear_shape()
		if not bc.is_empty():
			return bc
		var combo := _pick_combo_shape()
		if not combo.is_empty():
			return combo
		var fill := _pick_fitting(_fill_pool())
		if not fill.is_empty():
			return fill
		return _pick_helpful_shape()
	var smart_p : float = clampf(0.35 * (1.0 - float(placements) / SMART_FADE_MOVES), 0.0, 0.35)
	if randf() < smart_p:
		var smart := _pick_combo_shape()
		if not smart.is_empty():
			return smart
		# Past the early phase, when nothing completes a line, give big "builder"
		# mass so multi-clears build up. EARLY on we skip this — small pieces keep
		# the board low so clears keep emptying it (the fast board-clear loop).
		if sets_given >= EARLY_CLEAR_SETS:
			var fitting : Array = []
			for bs in BUILDER_SHAPES:
				for r in GRID_ROWS:
					var fits := false
					for c in GRID_COLS:
						if grid.can_place(bs, r, c):
							fits = true; break
					if fits:
						fitting.append(bs)
						break
			if not fitting.is_empty():
				return fitting[randi() % fitting.size()]
		return _pick_helpful_shape()
	# Adversarial pressure: the deeper the run, the more often we deliberately hand a
	# crowding, hard-to-place piece instead of a helpful one. This is the main reason
	# high scores stay hard now instead of plateauing into a comfortable groove.
	if randf() < _hard_bias():
		var mean := _pick_adversarial_shape()
		if not mean.is_empty():
			return mean
	if randf() < _progression():
		return SHAPES[randi() % SHAPES.size()]
	return _pick_helpful_shape()

# Find the shape with the highest line-clear potential anywhere on the board.
# Multi-line completions (the big combos) win outright; ties break randomly
# so the player doesn't get the same gift shape every time.
# Uses precomputed row/col fill counts so the full shape×position sweep stays
# cheap enough for set-spawn on mobile (can_place guarantees no overlap, so
# fill + shape-cells-in-line == line length means the line completes).
func _pick_combo_shape(pool: Array = SHAPES) -> Array:
	var row_fill : Array = []
	var col_fill : Array = []
	for r in GRID_ROWS:
		var n := 0
		for c in GRID_COLS:
			if grid.cells[r][c] != null: n += 1
		row_fill.append(n)
	for c in GRID_COLS:
		var n := 0
		for r in GRID_ROWS:
			if grid.cells[r][c] != null: n += 1
		col_fill.append(n)

	var best_lines := 0
	var candidates : Array = []
	for s in pool:
		var s_best := 0
		for r in GRID_ROWS:
			for c in GRID_COLS:
				if not grid.can_place(s, r, c):
					continue
				var rows_touched := {}
				var cols_touched := {}
				for cell in s:
					var rr : int = r + cell[1]
					var cc : int = c + cell[0]
					rows_touched[rr] = rows_touched.get(rr, 0) + 1
					cols_touched[cc] = cols_touched.get(cc, 0) + 1
				var n := 0
				for rr in rows_touched:
					if row_fill[rr] + rows_touched[rr] == GRID_COLS: n += 1
				for cc in cols_touched:
					if col_fill[cc] + cols_touched[cc] == GRID_ROWS: n += 1
				if n > s_best:
					s_best = n
		if s_best > best_lines:
			best_lines = s_best
			candidates = [s]
		elif s_best == best_lines and s_best > 0:
			candidates.append(s)
	if best_lines >= 1 and not candidates.is_empty():
		return candidates[randi() % candidates.size()]
	return []

# Find a shape that, placed somewhere, would clear the ENTIRE board (every filled
# cell ends up in a completed row/col). Returns [] if no single piece can do it.
func _pick_board_clear_shape() -> Array:
	var filled : Array = []
	for r in GRID_ROWS:
		for c in GRID_COLS:
			if grid.cells[r][c] != null:
				filled.append(Vector2i(c, r))
	if filled.is_empty():
		return []
	var row_fill : Array = []
	var col_fill : Array = []
	for r in GRID_ROWS:
		var n := 0
		for c in GRID_COLS:
			if grid.cells[r][c] != null: n += 1
		row_fill.append(n)
	for c in GRID_COLS:
		var n := 0
		for r in GRID_ROWS:
			if grid.cells[r][c] != null: n += 1
		col_fill.append(n)
	var cands : Array = []
	for s in SHAPES:
		var works := false
		for r in GRID_ROWS:
			for c in GRID_COLS:
				if not grid.can_place(s, r, c):
					continue
				var rt := {}
				var ct := {}
				for cell in s:
					rt[r + cell[1]] = rt.get(r + cell[1], 0) + 1
					ct[c + cell[0]] = ct.get(c + cell[0], 0) + 1
				var crows := {}
				var ccols := {}
				for rr in rt:
					if row_fill[rr] + rt[rr] == GRID_COLS: crows[rr] = true
				for cc in ct:
					if col_fill[cc] + ct[cc] == GRID_ROWS: ccols[cc] = true
				if crows.is_empty() and ccols.is_empty():
					continue
				var ok := true
				for fc in filled:
					if not crows.has(fc.y) and not ccols.has(fc.x):
						ok = false; break
				if ok:
					for cell in s:
						if not crows.has(r + cell[1]) and not ccols.has(c + cell[0]):
							ok = false; break
				if ok:
					works = true; break
			if works: break
		if works: cands.append(s)
	if cands.is_empty():
		return []
	return cands[randi() % cands.size()]

# A random shape from `pool` that fits somewhere (pool duplicates weight the odds).
# Returns [] if nothing fits.
func _pick_fitting(pool: Array) -> Array:
	var fitting : Array = []
	for s in pool:
		for r in GRID_ROWS:
			var ok := false
			for cc in GRID_COLS:
				if grid.can_place(s, r, cc):
					ok = true; break
			if ok:
				fitting.append(s)
				break
	if fitting.is_empty():
		return []
	return fitting[randi() % fitting.size()]

func _pick_helpful_shape() -> Array:
	var best_row    := -1
	var best_filled := 0
	for r in GRID_ROWS:
		var filled := 0
		for c in GRID_COLS:
			if grid.cells[r][c] != null:
				filled += 1
		if filled > best_filled and filled < GRID_COLS:
			best_filled = filled
			best_row    = r

	if best_row >= 0 and best_filled >= 3:
		var max_gap := 0
		var run     := 0
		for c in GRID_COLS:
			if grid.cells[best_row][c] == null:
				run += 1
				max_gap = max(max_gap, run)
			else:
				run = 0
		max_gap = min(max_gap, 5)
		if max_gap >= 1:
			var gap_shape: Array = []
			for i in max_gap:
				gap_shape.append([i, 0])
			for r in GRID_ROWS:
				for c in GRID_COLS:
					if grid.can_place(gap_shape, r, c):
						return gap_shape

	var candidates: Array = []
	for s in EARLY_SHAPES:
		var fits := false
		for r in GRID_ROWS:
			for c in GRID_COLS:
				if grid.can_place(s, r, c):
					fits = true; break
			if fits: break
		if fits: candidates.append(s)
	if not candidates.is_empty():
		return candidates[randi() % candidates.size()]

	var any_fitting: Array = []
	for s in SHAPES:
		var fits := false
		for r in GRID_ROWS:
			for c in GRID_COLS:
				if grid.can_place(s, r, c):
					fits = true; break
			if fits: break
		if fits: any_fitting.append(s)
	if not any_fitting.is_empty():
		return any_fitting[randi() % any_fitting.size()]

	return SHAPES[randi() % SHAPES.size()]

func _shapes_array() -> Array:
	var arr: Array = []
	for p in pieces:
		arr.append(p.shape)
	return arr

# ── Run restore (menu-continue = exact, watch-ad = with gift rows) ───────────
func _restore_state() -> void:
	score         = GameState.save_score
	sets_given    = GameState.save_sets_given
	lines_cleared = GameState.save_lines_cleared
	combo         = GameState.save_combo
	placements    = GameState.save_placements
	max_combo     = GameState.save_max_combo
	board_clears  = GameState.save_board_clears
	meter         = GameState.save_meter
	theme_idx     = GameState.theme_idx % THEMES.size()
	curr_bg       = THEMES[_visual_idx()]["bg"]
	prev_bg       = curr_bg
	theme_lerp    = 1.0
	_apply_block_style()

	for r in GRID_ROWS:
		for c in GRID_COLS:
			grid.cells[r][c] = GameState.save_cells[r][c]
			if not GameState.save_seeds.is_empty():
				grid.seeds[r][c] = GameState.save_seeds[r][c]

	if GameState.continue_mode == "ad":
		_help_player_continue()

	pieces = GameState.save_pieces.duplicate(true)
	placed = GameState.save_placed.duplicate()

	disp_score = float(score)   # show restored score instantly, no count-up
	_set_score_text(score)
	_update_combo_label()
	grid.queue_redraw()
	queue_redraw()

func _help_player_continue() -> void:
	var row_fills: Array = []
	for r in GRID_ROWS:
		var count := 0
		for c in GRID_COLS:
			if grid.cells[r][c] != null: count += 1
		row_fills.append({"r": r, "count": count})
	row_fills.sort_custom(func(a, b): return a["count"] > b["count"])
	for i in min(2, row_fills.size()):
		if row_fills[i]["count"] == 0: break
		var r : int = row_fills[i]["r"]
		for c in GRID_COLS:
			grid.cells[r][c] = null

# ── Input ─────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if menu_open:
		return
	# During a gated tutorial beat the coach's veil handles the tap to advance
	if tutorial != null and tutorial.gated:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed: _start_drag(event.position)
		else:             _end_drag(event.position)
	elif event is InputEventMouseMotion and dragging_slot >= 0:
		drag_pos = event.position
		_update_ghost()
		queue_redraw()
	elif event is InputEventScreenTouch:
		if event.pressed: _start_drag(event.position)
		else:             _end_drag(event.position)
	elif event is InputEventScreenDrag and dragging_slot >= 0:
		drag_pos = event.position
		_update_ghost()
		queue_redraw()

func _start_drag(pos: Vector2) -> void:
	if power_busy:
		return
	# Tap the power orb to spend the meter on the best ability it can afford
	if meter >= METER_BOMB and POWER_CENTER.distance_to(pos) <= POWER_R + 10.0:
		_fire_power()
		return
	if GEAR_RECT.grow(8).has_point(pos):
		_toggle_pause_menu()
		return
	var slot := _pos_to_slot(pos)
	# Guided placement: only the highlighted piece can be picked up
	if tut_lock_slot >= 0 and slot != tut_lock_slot:
		return
	if slot >= 0 and not placed[slot]:
		dragging_slot = slot
		drag_pos      = pos
		drag_pop_t    = 1.0
		snap_anchor   = Vector2i(-999, -999)   # fresh hysteresis lock for this piece
		last_hover_valid = false   # so the first valid hover this drag ticks
		Sfx.play_pickup()
		_spawn_sparkles(pos + Vector2(0, -DRAG_LIFT), 5, 26.0)
		queue_redraw()

func _end_drag(pos: Vector2) -> void:
	if dragging_slot < 0:
		return
	var lifted := pos + Vector2(0, -DRAG_LIFT)
	var shape : Array    = pieces[dragging_slot].shape
	var color : Color    = pieces[dragging_slot].color
	var snap  : Vector2i = _best_snap(lifted, shape)
	# Guided placement: drop anywhere on the board → lands on the one legal cell
	if tut_lock_slot == dragging_slot:
		snap = tut_lock_cell

	if _drop_targets_board(pos) and grid.can_place(shape, snap.y, snap.x):
		grid.place(shape, snap.y, snap.x, color, pieces[dragging_slot].get("pattern", 0))
		placed[dragging_slot] = true
		Sfx.play_place()
		_spawn_sparkles(Vector2(GRID_X + (grid.last_place_center.x + 0.5) * GRID_STEP,
			GRID_Y + (grid.last_place_center.y + 0.5) * GRID_STEP), 10, 46.0)

		var cells_cleared : int = grid.check_and_clear()
		var lines         : int = grid.last_lines_cleared

		if lines > 0:
			combo += 1
			max_combo = maxi(max_combo, combo)
			Sfx.play_clear(lines)
			Sfx.play_combo(combo)
			_buzz(30 + lines * 12)
			# Clears charge the power meter (multi-clears fill faster)
			meter = minf(meter + float(lines) * METER_PER_LINE, METER_FULL)
			# Big simultaneous clears rattle the board
			if lines >= 3:
				shake_t = maxf(shake_t, 0.15 + 0.06 * float(lines))
		else:
			if combo >= 2:
				streak_lost_t = 1.0   # flash the meter before it disappears
			combo = 0
			_buzz(12)

		# Streak multiplier applies to CLEAR points only — placement stays
		# cheap so clears remain the engine of the score
		var streak_mult : float = 1.0
		if combo > 1:
			streak_mult = minf(1.0 + STREAK_STEP * float(combo - 1), STREAK_CAP)
		var clear_pts : int = 0
		if lines > 0:
			clear_pts = int(round((cells_cleared * CELL_POINTS
				+ MULTI_BONUS[mini(lines, MULTI_BONUS.size() - 1)]) * streak_mult))

		# Depth scaling: the same move pays more the deeper you are in the run
		var depth_mult : float = minf(1.0 + DEPTH_STEP * float(placements), DEPTH_CAP)
		var gained : int = int(round((float(shape.size()) + float(clear_pts)) * depth_mult))

		if grid.is_board_empty():
			gained += BOARD_CLEAR_PTS
			board_clears += 1
			sets_since_clear = 0
			Sfx.play_board_clear()
			_buzz(90)
			_show_board_clear_popup()
			_trigger_board_clear_fx()

		score += gained
		GameState.submit_score(score)
		_check_achievements(lines)
		_refresh_best()
		_pop_score(gained)
		_show_score_popup(gained, lines, combo)
		_show_clear_text(lines)
		_update_combo_label()

		placements    += 1
		lines_cleared += grid.last_lines_cleared

		# Theme advances on GLOBAL lines across all runs — fresh backgrounds
		# keep coming no matter how short each game is
		if grid.last_lines_cleared > 0:
			@warning_ignore("integer_division")
			var old_bracket : int = GameState.total_lines / THEME_INTERVAL
			GameState.add_lines(grid.last_lines_cleared)
			@warning_ignore("integer_division")
			var new_bracket : int = GameState.total_lines / THEME_INTERVAL
			if new_bracket > old_bracket:
				_advance_theme()

		if placed[0] and placed[1] and placed[2]:
			_spawn_pieces()
		elif not grid.can_any_fit(_shapes_array(), placed):
			_try_game_over()

		_save_run()
		if tutorial != null:
			tutorial.on_event("placed", lines)
	elif _drop_targets_board(pos):
		Sfx.play_invalid()
		_buzz(25)

	dragging_slot = -1
	grid.clear_ghost()
	queue_redraw()

# Light haptic tap — no-ops on desktop and respects the settings toggle
var _last_buzz_ms : int = 0
func _buzz(ms: int) -> void:
	if not GameState.haptics_on:
		return
	# Throttle + clamp: rapid events (e.g. ghost-hover jitter at a snap/tray edge)
	# could otherwise stack handheld vibrations into a continuous buzz that only
	# stops on an app restart. One short pulse at a time, capped length.
	var now := Time.get_ticks_msec()
	if now - _last_buzz_ms < 50:
		return
	_last_buzz_ms = now
	Input.vibrate_handheld(clampi(ms, 1, 160))

# ── Power abilities ───────────────────────────────────────────────────────────
func _fire_power() -> void:
	if power_busy or dragging_slot >= 0:
		return
	power_pulse = 1.0
	Sfx.play_tick()
	if meter >= METER_FULL:
		meter = 0.0
		_power_gravity()
	elif meter >= METER_LASER:
		meter = 0.0          # double bomb spends the whole meter
		_power_twin_bomb()
	elif meter >= METER_BOMB:
		meter -= METER_BOMB
		_power_bomb()
	# Count the ability use → can pop the Powerhouse achievement mid-run
	GameState.add_power_used()
	for key in GameState.check_unlocks():
		_show_achievement_toast(key)
	if tutorial != null:
		tutorial.on_event("power", 0)
	queue_redraw()

# Prefer a filled cell so the blast always feels like it hit something
func _random_board_target() -> Vector2i:
	var filled : Array = []
	for r in GRID_ROWS:
		for c in GRID_COLS:
			if grid.cells[r][c] != null:
				filled.append(Vector2i(c, r))
	if filled.is_empty():
		return Vector2i(randi() % GRID_COLS, randi() % GRID_ROWS)
	return filled[randi() % filled.size()]

# A board cell at least `min_sep` cells (Chebyshev) away from `from`, preferring a
# filled cell so the second twin bomb hits something AND stays visually separated.
func _far_target(from: Vector2i, min_sep: int) -> Vector2i:
	var far_filled : Array = []
	var far_any    : Array = []
	for r in GRID_ROWS:
		for c in GRID_COLS:
			if maxi(absi(c - from.x), absi(r - from.y)) < min_sep:
				continue
			var cc := Vector2i(c, r)
			far_any.append(cc)
			if grid.cells[r][c] != null:
				far_filled.append(cc)
	if not far_filled.is_empty():
		return far_filled[randi() % far_filled.size()]
	if not far_any.is_empty():
		return far_any[randi() % far_any.size()]
	return Vector2i((from.x + GRID_COLS / 2) % GRID_COLS, (from.y + GRID_ROWS / 2) % GRID_ROWS)

func _power_bomb() -> void:
	power_busy = true
	var target := _random_board_target()
	var sp := Vector2(GRID_X + float(target.x) * GRID_STEP + CELL * 0.5,
		GRID_Y + float(target.y) * GRID_STEP + CELL * 0.5)
	effects.append({"type": "bomb_drop", "t": 0.0, "dur": 0.42, "pos": sp})
	fx_layer.queue_redraw()
	Sfx.play_pickup()
	await get_tree().create_timer(0.42).timeout
	effects.append({"type": "bomb_blast", "t": 0.0, "dur": 0.65, "pos": sp})
	shake_t   = maxf(shake_t, 0.45)
	flash_t   = maxf(flash_t, 0.6)
	flash_col = Color(1.0, 0.7, 0.3, 1.0)
	_buzz(60)
	Sfx.play_board_clear()
	var cleared := grid.bomb_clear(target.y, target.x, 1)
	_award_power_clear(cleared, 0)
	await get_tree().create_timer(0.45).timeout
	power_busy = false
	queue_redraw()

func _power_twin_bomb() -> void:
	power_busy = true
	# Twin bomb: two bombs in clearly DIFFERENT places — t2 is at least 3 cells from t1
	# so the two 3x3 blasts never overlap (no "both bombs in the same spot").
	var t1 := _random_board_target()
	var t2 := _far_target(t1, 3)
	var targets : Array = [t1, t2]

	for tg : Vector2i in targets:
		var sp := Vector2(GRID_X + float(tg.x) * GRID_STEP + CELL * 0.5,
			GRID_Y + float(tg.y) * GRID_STEP + CELL * 0.5)
		effects.append({"type": "bomb_drop", "t": 0.0, "dur": 0.42, "pos": sp})
	fx_layer.queue_redraw()
	Sfx.play_pickup()
	await get_tree().create_timer(0.42).timeout

	# Union of both 3×3 blasts (overlaps de-duped) → one shatter pass for both
	var cell_list : Array = []
	var seen : Dictionary = {}
	for tg : Vector2i in targets:
		var sp := Vector2(GRID_X + float(tg.x) * GRID_STEP + CELL * 0.5,
			GRID_Y + float(tg.y) * GRID_STEP + CELL * 0.5)
		effects.append({"type": "bomb_blast", "t": 0.0, "dur": 0.65, "pos": sp})
		for dr in range(-1, 2):
			for dc in range(-1, 2):
				var r := tg.y + dr
				var c := tg.x + dc
				if r >= 0 and r < GRID_ROWS and c >= 0 and c < GRID_COLS:
					var key := Vector2i(c, r)
					if not seen.has(key):
						seen[key] = true
						cell_list.append(key)
	shake_t   = maxf(shake_t, 0.50)
	flash_t   = maxf(flash_t, 0.60)
	flash_col = Color(1.0, 0.7, 0.3, 1.0)
	_buzz(70)
	Sfx.play_board_clear()
	var cleared := grid.pop_cells(cell_list, Vector2((t1.x + t2.x) * 0.5, (t1.y + t2.y) * 0.5))
	_award_power_clear(cleared, 0)
	await get_tree().create_timer(0.45).timeout
	power_busy = false
	queue_redraw()

func _power_gravity() -> void:
	power_busy = true
	var dirs : Array = [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
	var dir : Vector2i = dirs[randi() % dirs.size()]
	effects.append({"type": "gravity", "t": 0.0, "dur": 0.85, "dir": Vector2(dir)})
	fx_layer.queue_redraw()
	flash_t   = 1.0
	flash_col = Color(1.0, 0.92, 0.5, 1.0)
	Sfx.play_combo(4)
	grid.start_slam(dir)
	await get_tree().create_timer(Grid.SLAM_DUR + 0.04).timeout
	shake_t = maxf(shake_t, 0.65)
	_buzz(120)
	Sfx.play_board_clear()
	# Slammed so hard the impact edge shatters — plus any line it completed
	var cleared := grid.slam_clear(dir)
	var lines := grid.last_lines_cleared
	_award_power_clear(cleared, lines)
	await get_tree().create_timer(0.45).timeout
	# Bounce everything to the wall ONCE more so the shattered impact layer leaves
	# no gap — blocks re-settle flush against the wall.
	grid.start_slam(dir)
	await get_tree().create_timer(Grid.SLAM_DUR + 0.04).timeout
	# Final impact: the re-settled layer slams flush into the wall — one more thud
	shake_t = maxf(shake_t, 0.50)
	_buzz(90)
	var settled := grid.check_and_clear()
	if settled > 0:
		_award_power_clear(settled, grid.last_lines_cleared)
		await get_tree().create_timer(0.4).timeout
	else:
		await get_tree().create_timer(0.12).timeout
	power_busy = false
	queue_redraw()

# Score + popups for cells removed by an ability (no streak — it's not a placement)
func _award_power_clear(cells_cleared: int, lines: int) -> void:
	if cells_cleared <= 0:
		return
	var depth_mult : float = minf(1.0 + DEPTH_STEP * float(placements), DEPTH_CAP)
	var pts : int = int(round(float(cells_cleared) * CELL_POINTS * depth_mult))
	if lines >= 2:
		pts += int(round(float(MULTI_BONUS[mini(lines, MULTI_BONUS.size() - 1)]) * depth_mult))
	if grid.is_board_empty():
		pts += BOARD_CLEAR_PTS
		board_clears += 1
		sets_since_clear = 0
		Sfx.play_board_clear()
		_show_board_clear_popup()
	else:
		# Rainbow praise scaled to how much the ability cleared.
		_show_praise(_praise_tier_for_cells(cells_cleared))
	score += pts
	GameState.submit_score(score)
	lines_cleared += lines
	_check_achievements(lines)
	_refresh_best()
	_pop_score(pts)
	_show_score_popup(pts, maxi(lines, 1), 1)
	_save_run()

# ── Achievements ──────────────────────────────────────────────────────────────
# Push run-live values into the lifetime stats, then unlock anything earned.
# (Blocks/games/board totals roll up at game over; these can pop mid-run.)
func _check_achievements(lines_this_move: int) -> void:
	GameState.stat_best_streak = maxi(GameState.stat_best_streak, combo)
	GameState.stat_best_multi  = maxi(GameState.stat_best_multi, lines_this_move)
	for key in GameState.check_unlocks():
		_show_achievement_toast(key)

func _show_achievement_toast(id: String) -> void:
	var a : Dictionary = GameState.ach_info(id)
	if a.is_empty():
		return
	var is_skin : bool = a.get("skin", false)
	Sfx.play_best()
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.11, 0.20, 0.96)
	sb.set_corner_radius_all(16)
	sb.border_width_bottom = 5
	sb.border_color = Color(0.40, 0.85, 1.0) if is_skin else Color(0.95, 0.75, 0.15)
	sb.content_margin_left = 18; sb.content_margin_right = 18
	sb.content_margin_top = 10;  sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(330, 0)
	panel.position = Vector2(42, -90)
	ui.add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	var header := Label.new()
	header.text = "NEW SKIN UNLOCKED" if is_skin else "ACHIEVEMENT UNLOCKED"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", Color(1, 1, 1, 0.50))
	vbox.add_child(header)
	var title := Label.new()
	title.text = a["name"] if (is_skin or int(a["xp"]) == 0) else a["name"] + "   +" + str(a["xp"]) + " XP"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.55, 0.90, 1.0) if is_skin else Color(0.95, 0.78, 0.20))
	vbox.add_child(title)
	var desc := Label.new()
	desc.text = a["desc"]
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	vbox.add_child(desc)

	var t := create_tween()
	t.tween_property(panel, "position:y", 88.0, 0.40).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(2.4)
	t.tween_property(panel, "position:y", -110.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(panel.queue_free)

# Dev skin override (main-menu picker) wins over the theme — and drives the
# WHOLE visual set (blocks, background colour, pattern, orbs), not just blocks
func _visual_idx() -> int:
	return GameState.effective_skin(theme_idx)

func _apply_block_style() -> void:
	grid.block_style = _visual_idx()

func _update_ghost() -> void:
	if dragging_slot < 0 or placed[dragging_slot]:
		return
	# Off the board (or finger in the tray) → hide the ghost so it's clear it won't place
	if not _drop_targets_board(drag_pos):
		grid.clear_ghost()
		last_hover_valid = false
		return
	var shape : Array    = pieces[dragging_slot].shape
	var snap  : Vector2i = _best_snap(drag_pos + Vector2(0, -DRAG_LIFT), shape)
	# Guided placement magnetises the ghost to the single legal cell
	if tut_lock_slot == dragging_slot:
		snap = tut_lock_cell
	if grid.can_place(shape, snap.y, snap.x):
		grid.set_ghost(shape, snap.y, snap.x, pieces[dragging_slot].color)
		# Light tick each time the shadow lands on a NEW valid spot
		if not last_hover_valid or snap != last_hover_snap:
			_buzz(8)
		last_hover_valid = true
		last_hover_snap  = snap
	else:
		grid.clear_ghost()
		last_hover_valid = false

func _get_snap(pos: Vector2, shape: Array) -> Vector2i:
	var min_c := 99; var max_c := 0
	var min_r := 99; var max_r := 0
	for cell in shape:
		if (cell[0] as int) < min_c: min_c = cell[0]
		if (cell[0] as int) > max_c: max_c = cell[0]
		if (cell[1] as int) < min_r: min_r = cell[1]
		if (cell[1] as int) > max_r: max_r = cell[1]
	# Centre the shape's bounding box on the (lifted) finger point — matching how the
	# dragged piece is drawn — then round with symmetric hysteresis. Accounts for the
	# DRAG_LIFT offset because `pos` is already the lifted point.
	var cx : float = (float(min_c) + float(max_c)) * 0.5
	var cy : float = (float(min_r) + float(max_r)) * 0.5
	var fx : float = (pos.x - GRID_X) / GRID_STEP - cx - 0.5
	var fy : float = (pos.y - GRID_Y) / GRID_STEP - cy - 0.5
	var fresh : bool = snap_anchor.x < -900
	var pc : int = _hyst_round(fx, snap_anchor.x, fresh)
	var pr : int = _hyst_round(fy, snap_anchor.y, fresh)
	snap_anchor = Vector2i(pc, pr)
	return Vector2i(pc, pr)

# Generous snap: if the raw cell isn't placeable, fall to the nearest placeable
# spot within ±SNAP_REACH cells so the shadow forgives near-misses on fast play.
func _best_snap(pos: Vector2, shape: Array) -> Vector2i:
	var base := _get_snap(pos, shape)
	if grid.can_place(shape, base.y, base.x):
		return base
	var best := base
	var best_d := 99.0
	for dr in range(-SNAP_REACH, SNAP_REACH + 1):
		for dc in range(-SNAP_REACH, SNAP_REACH + 1):
			if grid.can_place(shape, base.y + dr, base.x + dc):
				var d := Vector2(dc, dr).length()
				if d < best_d:
					best_d = d
					best = Vector2i(base.x + dc, base.y + dr)
	return best

# Round f to the nearest cell, but HOLD the previous placement until f moves
# SNAP_HYST past the half-cell switch point — symmetric on all sides.
func _hyst_round(f: float, prev: int, fresh: bool) -> int:
	if fresh:
		return roundi(f)
	if f >= float(prev) + 0.5 + SNAP_HYST:
		return roundi(f)
	if f < float(prev) - 0.5 - SNAP_HYST:
		return roundi(f)
	return prev

func _screen_to_grid(pos: Vector2) -> Vector2i:
	return Vector2i(
		int((pos.x - GRID_X) / GRID_STEP),
		int((pos.y - GRID_Y) / GRID_STEP)
	)

func _pos_to_slot(pos: Vector2) -> int:
	if pos.y < TRAY_Y or pos.y > TRAY_Y + TRAY_H:
		return -1
	for i in 3:
		if pos.x >= i * SLOT_W and pos.x < (i + 1) * SLOT_W:
			return i
	return -1

# ── Theme ─────────────────────────────────────────────────────────────────────
func _advance_theme() -> void:
	# AUTO cycles through every unlocked skin (shuffle bag) before any repeats
	theme_idx = GameState.next_auto_theme(theme_idx)
	GameState.set_theme(theme_idx)
	# Skin pinned (player lock): progression still ticks, but the visuals —
	# block style, background, orbs, flash, theme popup — stay put.
	if GameState.skin_locked:
		return
	prev_bg    = curr_bg
	curr_bg    = THEMES[theme_idx]["bg"]
	theme_lerp = 0.0

	var orb_col: Color = THEMES[theme_idx]["orb"]
	for orb in orbs:
		orb["color"] = Color(orb_col.r, orb_col.g, orb_col.b, orb["color"].a)
	orb_boost = 2.0   # transient whoosh on biome change — decays in _process, never compounds (was *=1.4 which compounded into runaway speed)

	_apply_block_style()

	# Screen shake
	shake_t = 0.50

	# Bright flash in the theme's accent colour
	flash_col = Color(
		minf(orb_col.r * 4.0, 1.0),
		minf(orb_col.g * 4.0, 1.0),
		minf(orb_col.b * 4.0, 1.0),
		1.0
	)
	flash_t = 1.0

	Sfx.play_theme()
	_show_theme_popup(THEMES[theme_idx]["name"])

func _show_theme_popup(theme_name: String) -> void:
	_enqueue_banner(_spawn_theme_banner.bind(theme_name), 1.3)

func _spawn_theme_banner(theme_name: String) -> void:
	var accent : Color = THEMES[theme_idx]["accent"]
	var cy := 360.0   # over the board centre — a real "you've arrived" moment

	# Whole reveal lives under one Control so it pops + fades as a single unit
	var root := Control.new()
	root.position = Vector2.ZERO
	root.size = Vector2(414, 896)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE   # never blocks placing pieces
	ui.add_child(root)

	# Banner band + accent edge lines
	var band := ColorRect.new()
	band.color = Color(0.05, 0.04, 0.10, 0.55)
	band.position = Vector2(0, cy - 66)
	band.size = Vector2(414, 132)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(band)
	for ey : float in [cy - 66.0, cy + 63.0]:
		var line := ColorRect.new()
		line.color = Color(accent.r, accent.g, accent.b, 0.9)
		line.position = Vector2(0, ey)
		line.size = Vector2(414, 3)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(line)

	# "ENTERING" eyebrow
	var eyebrow := Label.new()
	eyebrow.text = "ENTERING"
	eyebrow.add_theme_font_size_override("font_size", 17)
	eyebrow.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.85))
	eyebrow.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.09, 0.8))
	eyebrow.add_theme_constant_override("outline_size", 4)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.position = Vector2(0, cy - 52)
	eyebrow.size = Vector2(414, 22)
	eyebrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(eyebrow)

	# Area name — big and bold
	var lbl := Label.new()
	lbl.text = theme_name
	lbl.add_theme_font_size_override("font_size", 44)
	lbl.add_theme_color_override("font_color", accent)
	lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.09, 0.9))
	lbl.add_theme_constant_override("outline_size", 7)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(0, cy - 28)
	lbl.size = Vector2(414, 58)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lbl)

	# Pop in (scale + fade), hold, then drift out
	root.pivot_offset = Vector2(207, cy)
	root.modulate.a = 0.0
	root.scale = Vector2(0.80, 0.80)
	var t := create_tween()
	t.tween_property(root, "modulate:a", 1.0, 0.28)
	t.parallel().tween_property(root, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(1.2)
	t.tween_property(root, "modulate:a", 0.0, 0.5)
	t.parallel().tween_property(root, "scale", Vector2(1.10, 1.10), 0.5)
	t.chain().tween_callback(root.queue_free)

# ── Drawing ───────────────────────────────────────────────────────────────────
func _draw() -> void:
	# Apply shake to all background / tray drawing
	draw_set_transform(shake_offset)

	# Background
	var bg : Color = prev_bg.lerp(curr_bg, theme_lerp)
	draw_rect(Rect2(Vector2.ZERO, Vector2(414, 896)), bg, true)

	# Per-theme background pattern
	_draw_bg_pattern()

	# Orbs
	for orb in orbs:
		draw_circle(orb["pos"], orb["radius"], orb["color"])

	# Transition flash overlay
	if flash_t > 0.0:
		draw_rect(Rect2(Vector2.ZERO, Vector2(414, 896)),
			Color(flash_col.r, flash_col.g, flash_col.b, flash_t * 0.40), true)

	# Score floats as an outlined candy numeral (no box). A soft biome-accent halo
	# behind it gives each skin its own personality; the best pill is accent-tinted.
	var sacc : Color = THEMES[_visual_idx()]["accent"]
	# As the score climbs the halo blends to rainbow + grows/brightens (matches the
	# rainbow score numeral). score_glow is 0..1 (half@50k, full@100k), set in _process.
	var glow_col : Color = sacc
	if score_glow > 0.0:
		glow_col = sacc.lerp(_score_shimmer_color(), score_glow)
	draw_circle(Vector2(207, 66), 98.0 + score_glow * 22.0, Color(glow_col.r, glow_col.g, glow_col.b, 0.07 + score_glow * 0.10))
	draw_circle(Vector2(207, 66), 62.0 + score_glow * 12.0, Color(glow_col.r, glow_col.g, glow_col.b, 0.09 + score_glow * 0.12))
	if score_glow > 0.0:
		draw_circle(Vector2(207, 66), 132.0, Color(glow_col.r, glow_col.g, glow_col.b, score_glow * 0.06))
	var bpill := Rect2(132, 125, 150, 31)
	_rr_fill(bpill, 15.0, Color(0, 0, 0, 0.32))
	_rr_fill(bpill, 15.0, Color(sacc.r, sacc.g, sacc.b, 0.20))
	_rr_outline(bpill, 15.0, Color(sacc.r, sacc.g, sacc.b, 0.60), 1.5)

	# Settings gear button (top-right)
	_draw_gear_button()

	# Power orb (top-left)
	_draw_power_orb()

	# Streak meter (between grid and tray)
	if combo >= 2 or streak_lost_t > 0.0:
		_draw_streak_meter()

	# Grid backdrop
	var grid_rect := Rect2(GRID_X - 8, GRID_Y - 8,
		GRID_COLS * GRID_STEP + 14, GRID_ROWS * GRID_STEP + 14)
	_rr_fill(grid_rect, 14.0, Color(0, 0, 0, 0.28))
	# No generic outline — the per-skin reactive frame (Grid._draw) owns the board border

	# Tray
	for i in 3:
		_draw_slot(i)

	draw_set_transform(Vector2.ZERO)

	# NOTE: the power-rescue prompt is drawn on fx_layer (see _draw_fx_layer), NOT here.
	# Game._draw renders BEHIND child nodes (the Grid/board), so drawing it here would
	# hide it behind the board cells.

# "No moves — use your power!" alert: a pulsing ring on the orb + a banner.
# Draws on `ci` (the fx_layer canvas item) — NOT bare self.draw_*, which is invalid
# inside another node's draw signal (was erroring every frame, banner never appeared).
func _draw_rescue(ci: CanvasItem) -> void:
	var pulse := (sin(Time.get_ticks_msec() * 0.012) + 1.0) * 0.5
	# Strong pulsing ring around the power orb to pull the eye to it
	ci.draw_arc(POWER_CENTER, POWER_R + 9.0 + pulse * 5.0, 0, TAU, 40,
		Color(1.0, 0.85, 0.30, 0.55 + 0.40 * pulse), 3.5, true)
	# Cute bubbly red arrow bobbing toward the orb so it's obvious where to tap.
	# Built as ONE rounded polygon so a single clean outline wraps the whole shape.
	var u := (POWER_CENTER - Vector2(120.0, 132.0)).normalized()  # points up-left at the orb
	var v := Vector2(-u.y, u.x)
	var bob := 3.0 + pulse * 10.0
	var tip := POWER_CENTER - u * (POWER_R + 4.0 + bob)
	var hl := 22.0   # head length
	var hw := 24.0   # head half-width (fat, bubbly)
	var sl := 24.0   # shaft length
	var sw := 10.0   # shaft half-width
	var raw := PackedVector2Array([
		tip,
		tip - u * hl + v * hw,
		tip - u * hl + v * sw,
		tip - u * (hl + sl) + v * sw,
		tip - u * (hl + sl) - v * sw,
		tip - u * hl - v * sw,
		tip - u * hl - v * hw,
	])
	var arrow := _round_poly(raw, 7.0, 4)
	var arrow_outline := arrow
	arrow_outline.append(arrow[0])
	BlockSkins.draw_poly_safe(ci, arrow, Color(1.0, 0.30, 0.34, 0.95))  # candy-red fill
	ci.draw_polyline(arrow_outline, Color(1, 1, 1, 0.95), 3.5, true)    # one soft white outline
	# Alert banner across the board
	var panel := Rect2(47, 326, 320, 102)
	ci.draw_polygon(_rr_points(panel, 18.0), PackedColorArray([Color(0.12, 0.04, 0.06, 0.90)]))
	var outline := _rr_points(panel, 18.0)
	outline.append(outline[0])
	ci.draw_polyline(outline, Color(1.0, 0.40, 0.35, 0.45 + 0.40 * pulse), 2.5)
	var f := _icon_font
	ci.draw_string(f, Vector2(panel.position.x, 366), "NO MOVES LEFT!",
		HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 27, Color(1.0, 0.85, 0.40))
	ci.draw_string(f, Vector2(panel.position.x, 397), "Tap your POWER to survive",
		HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 18, Color(1, 1, 1, 0.88))
	var secs : int = int(ceil(rescue_timer))
	ci.draw_string(f, Vector2(panel.position.x, 420), str(secs),
		HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 15, Color(1, 1, 1, 0.55))

func _draw_bg_pattern() -> void:
	match _visual_idx():
		0:  # Pastel Sky — blue sky with drifting clouds and a soft sun
			var ct := Time.get_ticks_msec() * 0.001
			# Soft sun glow, top-left
			draw_circle(Vector2(62, 92), 72.0, Color(1.0, 0.96, 0.75, 0.10))
			draw_circle(Vector2(62, 92), 42.0, Color(1.0, 0.97, 0.82, 0.12))
			# Puffy clouds drifting across at different speeds
			for i in 6:
				var spd : float = 6.0 + float(i % 3) * 3.5
				var cx  : float = fmod(float(i * 157 + 40) * 13.7 + ct * spd, 514.0) - 50.0
				var cy  : float = 70.0 + float(i) * 135.0 + sin(ct * 0.3 + float(i) * 1.7) * 6.0
				var sc  : float = 0.8 + float(i % 3) * 0.35
				var cc  := Color(1, 1, 1, 0.13)
				draw_circle(Vector2(cx, cy), 26.0 * sc, cc)
				draw_circle(Vector2(cx + 22.0 * sc, cy + 6.0 * sc), 20.0 * sc, cc)
				draw_circle(Vector2(cx - 22.0 * sc, cy + 7.0 * sc), 18.0 * sc, cc)
				draw_circle(Vector2(cx + 6.0 * sc, cy - 13.0 * sc), 17.0 * sc, cc)
		1:  # Neon Jungle — scanlines + glowing vine zigzags
			for y_line in range(0, 896, 5):
				draw_line(Vector2(0, y_line), Vector2(414, y_line),
					Color(0, 0, 0, 0.07), 1.0)
			for v in 3:
				var vx : float = 60.0 + float(v) * 145.0
				var pts := PackedVector2Array()
				for k in 9:
					var vy := float(k) * 112.0
					pts.append(Vector2(vx + (18.0 if k % 2 == 0 else -18.0) + sin(float(v) * 2.0 + float(k)) * 8.0, vy))
				draw_polyline(pts, Color(0.20, 1.00, 0.45, 0.07), 2.5)
				# Leaf nubs at the bends
				for k in range(1, 8, 2):
					draw_circle(pts[k], 4.0, Color(0.20, 1.00, 0.45, 0.06))
		2:  # Circuit City — PCB traces with node dots
			var tc := Color(0.20, 0.95, 0.65, 0.05)
			for i in 6:
				var ty : float = 70.0 + float(i) * 150.0
				var bend_x : float = 60.0 + float((i * 73) % 280)
				draw_line(Vector2(0, ty), Vector2(bend_x, ty), tc, 1.5)
				draw_line(Vector2(bend_x, ty), Vector2(bend_x, ty + 80.0), tc, 1.5)
				draw_line(Vector2(bend_x, ty + 80.0), Vector2(414, ty + 80.0), tc, 1.5)
				draw_circle(Vector2(bend_x, ty), 3.0, Color(0.20, 0.95, 0.65, 0.10))
				draw_circle(Vector2(bend_x, ty + 80.0), 3.0, Color(0.20, 0.95, 0.65, 0.10))
		3:  # Brickyard — faint running-bond wall
			var bc2 := Color(0.95, 0.45, 0.25, 0.045)
			var brow := 0
			for by2 in range(0, 896, 44):
				draw_line(Vector2(0, by2), Vector2(414, by2), bc2, 1.5)
				var off := 0.0 if brow % 2 == 0 else 44.0
				for bx2 in range(0, 502, 88):
					draw_line(Vector2(float(bx2) + off, by2), Vector2(float(bx2) + off, by2 + 44.0), bc2, 1.5)
				brow += 1
		4:  # Crystal Cave — gem shards growing from the edges + floating ones
			var dt := Time.get_ticks_msec() * 0.001
			var shard_c := Color(0.40, 0.60, 1.0, 0.07)
			# Shard clusters along the bottom edge
			for i in 7:
				var sx2 : float = 20.0 + float(i) * 62.0
				var sh  : float = 40.0 + float((i * 37) % 50)
				draw_polygon(PackedVector2Array([
					Vector2(sx2 - 14.0, 896.0), Vector2(sx2 + float((i * 13) % 11) - 5.0, 896.0 - sh),
					Vector2(sx2 + 14.0, 896.0)]), PackedColorArray([shard_c]))
			# A few floating rotating shards
			for i in 4:
				var dx : float = fmod(float(i * 113 + 29) * 33.1, 414.0)
				var dy : float = 100.0 + fmod(float(i * 67 + 43) * 41.9, 600.0)
				var rot := dt * 0.25 * (1.0 if i % 2 == 0 else -1.0) + float(i)
				draw_set_transform(Vector2(dx, dy), rot)
				draw_polygon(PackedVector2Array([Vector2(-7, 12), Vector2(0, -14), Vector2(7, 12)]),
					PackedColorArray([shard_c]))
				draw_set_transform(Vector2.ZERO)
		5:  # Candy Land — slowly spinning wrapped candies
			var cdt := Time.get_ticks_msec() * 0.001
			for i in 8:
				var px : float = fmod(float(i * 131 + 37) * 29.7, 414.0)
				var py : float = fmod(float(i * 89  + 17) * 47.3, 896.0)
				var rot := cdt * 0.3 * (1.0 if i % 2 == 0 else -1.0) + float(i)
				var cs2 : float = 9.0 + float(i % 3) * 4.0
				var cc2 := Color(1.0, 0.55, 0.75, 0.07)
				draw_set_transform(Vector2(px, py), rot)
				draw_circle(Vector2.ZERO, cs2, cc2)
				# Wrapper twists
				draw_polygon(PackedVector2Array([Vector2(-cs2, 0), Vector2(-cs2 * 1.9, -cs2 * 0.7), Vector2(-cs2 * 1.9, cs2 * 0.7)]), PackedColorArray([cc2]))
				draw_polygon(PackedVector2Array([Vector2(cs2, 0),  Vector2(cs2 * 1.9, -cs2 * 0.7),  Vector2(cs2 * 1.9, cs2 * 0.7)]),  PackedColorArray([cc2]))
				# Stripe
				draw_line(Vector2(-cs2 * 0.5, -cs2 * 0.8), Vector2(-cs2 * 0.5, cs2 * 0.8), Color(1, 1, 1, 0.05), 2.0)
				draw_set_transform(Vector2.ZERO)
		6:  # Frozen Peak — falling six-arm snowflakes
			var drift := Time.get_ticks_msec() * 0.001
			for i in 14:
				var sx : float = fmod(float(i * 97 + 13) * 37.3 + drift * (6.0 + float(i % 5) * 3.0), 414.0)
				var sy : float = fmod(float(i * 53 + 71) * 19.7 + drift * (14.0 + float(i % 7) * 5.0), 896.0)
				var fs : float = 5.0 + float(i % 3) * 3.0
				var rot := drift * 0.4 + float(i)
				var fa  := Color(1, 1, 1, 0.08 + float(i % 3) * 0.03)
				draw_set_transform(Vector2(sx, sy), rot)
				for arm in 3:
					var a := float(arm) * PI / 3.0
					var dir := Vector2(cos(a), sin(a)) * fs
					draw_line(-dir, dir, fa, 1.2)
					# Side ticks on each arm
					draw_line(dir * 0.55, dir * 0.55 + dir.rotated(PI * 0.5) * 0.3, fa, 1.0)
					draw_line(dir * 0.55, dir * 0.55 + dir.rotated(-PI * 0.5) * 0.3, fa, 1.0)
				draw_set_transform(Vector2.ZERO)
		7:  # Meadow — falling petals + grass tufts along the bottom
			var pt := Time.get_ticks_msec() * 0.001
			for i in 12:
				var px : float = fmod(float(i * 131 + 31) * 23.9 + sin(pt * 0.8 + float(i)) * 20.0, 414.0)
				var py : float = fmod(float(i * 73 + 7) * 41.3 + pt * (8.0 + float(i % 4) * 4.0), 896.0)
				var rot := pt * 0.6 + float(i) * 1.3
				draw_set_transform(Vector2(px, py), rot)
				draw_polygon(PackedVector2Array([Vector2(0, -5), Vector2(3.5, 0), Vector2(0, 5), Vector2(-3.5, 0)]),
					PackedColorArray([Color(1.0, 0.55, 0.80, 0.12) if i % 3 == 0 else (Color(0.32, 0.92, 0.86, 0.11) if i % 3 == 1 else Color(0.85, 1.0, 0.65, 0.09))]))
				draw_set_transform(Vector2.ZERO)
			for i in 28:
				var gx2 : float = float(i) * 15.0 + float((i * 7) % 9)
				var gh  : float = 14.0 + float((i * 13) % 18) + sin(pt * 1.2 + float(i)) * 2.0
				draw_polygon(PackedVector2Array([
					Vector2(gx2 - 4.0, 896.0), Vector2(gx2 + float((i * 5) % 7) - 3.0, 896.0 - gh),
					Vector2(gx2 + 4.0, 896.0)]), PackedColorArray([Color(0.45, 0.95, 0.35, 0.07)]))
		8:  # Ocean — waves + little fish swimming by
			var ot := Time.get_ticks_msec() * 0.001
			for i in 7:
				var wy : float = 80.0 + float(i) * 120.0
				var pts := PackedVector2Array()
				for x in range(0, 415, 30):
					pts.append(Vector2(float(x), wy + sin(ot * 0.8 + float(i) * 1.7 + float(x) * 0.015) * 14.0))
				draw_polyline(pts, Color(0.30, 0.60, 1.0, 0.05), 2.0)
			for i in 4:
				var flip : float = 1.0 if i % 2 == 0 else -1.0
				var fx : float = fmod(ot * (26.0 + float(i) * 9.0) + float(i * 157), 514.0) - 50.0
				if flip < 0.0: fx = 414.0 - fx
				var fy : float = 150.0 + float(i) * 190.0 + sin(ot * 1.5 + float(i)) * 10.0
				var fc := Color(0.45, 0.75, 1.0, 0.09)
				draw_set_transform(Vector2(fx, fy), 0.0, Vector2(flip, 1.0))
				draw_circle(Vector2.ZERO, 7.0, fc)                       # body
				draw_circle(Vector2(3.0, -1.0), 5.0, fc)                  # head taper
				draw_polygon(PackedVector2Array([Vector2(-6, 0), Vector2(-13, -5), Vector2(-13, 5)]),
					PackedColorArray([fc]))                               # tail
				draw_set_transform(Vector2.ZERO)
		9:  # Volcano — flame embers rising + dark peak silhouette
			var vt := Time.get_ticks_msec() * 0.001
			draw_polygon(PackedVector2Array([
				Vector2(40, 896), Vector2(207, 660), Vector2(374, 896)]),
				PackedColorArray([Color(0.0, 0.0, 0.0, 0.18)]))
			draw_line(Vector2(190, 678), Vector2(224, 678), Color(1.0, 0.45, 0.08, 0.20), 3.0)
			for i in 14:
				var ex : float = fmod(float(i * 97 + 41) * 31.7 + sin(vt * 1.4 + float(i)) * 18.0, 414.0)
				var ey : float = fmod(float(i * 59 + 11) * 47.1 - vt * (22.0 + float(i % 5) * 9.0), 896.0)
				if ey < 0.0: ey += 896.0
				var es : float = 3.0 + float(i % 3) * 1.5
				var flick := sin(vt * 6.0 + float(i)) * es * 0.3
				draw_polygon(PackedVector2Array([
					Vector2(ex - es, ey), Vector2(ex + flick * 0.3, ey - es * 2.2 - flick),
					Vector2(ex + es, ey)]),
					PackedColorArray([Color(1.0, 0.45 + float(i % 3) * 0.12, 0.08, 0.10)]))
		10:  # Timber — stacked log pile + tumbling wood chips
			var wt3 := Time.get_ticks_msec() * 0.001
			var lc2 := Color(0.85, 0.60, 0.25, 0.07)
			# Log-end pyramid in the bottom corner
			for lp : Vector2 in [Vector2(40, 858), Vector2(96, 858), Vector2(152, 858),
					Vector2(68, 810), Vector2(124, 810), Vector2(96, 762)]:
				draw_arc(lp, 26.0, 0, TAU, 22, lc2, 2.0, false)
				draw_arc(lp, 15.0, 0, TAU, 16, Color(0.85, 0.60, 0.25, 0.05), 1.5, false)
				draw_circle(lp, 4.0, Color(0.85, 0.60, 0.25, 0.06))
			# A second smaller pile, top-right
			for lp2 : Vector2 in [Vector2(330, 60), Vector2(380, 60), Vector2(355, 18)]:
				draw_arc(lp2, 20.0, 0, TAU, 20, lc2, 1.8, false)
				draw_circle(lp2, 3.0, Color(0.85, 0.60, 0.25, 0.06))
			# Wood chips drifting down, tumbling
			for i in 8:
				var px4 : float = fmod(float(i * 131 + 41) * 27.9 + sin(wt3 * 0.7 + float(i)) * 14.0, 414.0)
				var py4 : float = fmod(float(i * 79 + 13) * 43.7 + wt3 * (9.0 + float(i % 4) * 4.0), 896.0)
				draw_set_transform(Vector2(px4, py4), wt3 * 1.2 + float(i) * 1.4)
				draw_rect(Rect2(-5, -2, 10, 4), Color(0.85, 0.62, 0.30, 0.08), true)
				draw_set_transform(Vector2.ZERO)
		11:  # Galaxy — stars, spiral arms, a ringed planet and a shooting star
			var gt := Time.get_ticks_msec() * 0.001
			for i in 40:
				var sx2 : float = fmod(float(i * 97 + 13) * 37.3, 414.0)
				var sy2 : float = fmod(float(i * 53 + 71) * 19.7, 896.0)
				var tw  : float = 0.05 + 0.15 * absf(sin(gt * 1.5 + float(i) * 1.1))
				draw_rect(Rect2(sx2, sy2, 2.0, 2.0), Color(1, 1, 1, tw), true)
			for i in 3:
				draw_arc(Vector2(207, 448), 100.0 + float(i) * 90.0,
					gt * 0.1 + float(i), gt * 0.1 + float(i) + PI * 1.2, 40,
					Color(0.75, 0.35, 1.0, 0.05), 2.0, false)
			# Ringed planet, top-right
			draw_circle(Vector2(340, 130), 22.0, Color(0.75, 0.35, 1.0, 0.10))
			draw_set_transform(Vector2(340, 130), -0.35, Vector2(1.0, 0.32))
			draw_arc(Vector2.ZERO, 34.0, 0, TAU, 32, Color(0.85, 0.55, 1.0, 0.10), 2.0, false)
			draw_set_transform(Vector2.ZERO)
			# Shooting star every ~7s — random direction and path each time,
			# streaking across the whole screen (behind the play area)
			var sw := fmod(gt, 7.0)
			if sw < 1.4:
				var k := sw / 1.4
				var shot := int(gt / 7.0)
				var h2 := absi(shot * 2654435761)
				var ang := float(h2 % 628) * 0.01
				# Aim through a random interior point so every streak crosses the screen
				var target := Vector2(80.0 + float((h2 / 7) % 254), 180.0 + float((h2 / 13) % 530))
				var dir := Vector2(cos(ang), sin(ang))
				var sp := target - dir * 600.0 + dir * 1200.0 * k
				var fade := sin(k * PI)
				draw_line(sp, sp - dir * (48.0 + 22.0 * fade), Color(1, 1, 1, 0.30 * fade), 2.0)
				draw_line(sp, sp - dir * 20.0, Color(1, 1, 1, 0.45 * fade), 3.0)
				draw_circle(sp, 2.6, Color(1, 1, 1, 0.60 * fade))
		12:  # The Hive — faint honeycomb lattice + busy bees
			var ht := Time.get_ticks_msec() * 0.001
			var hex_col := Color(1.0, 0.75, 0.20, 0.05)
			for row in 7:
				for hx in 4:
					var hcx := 50.0 + float(hx) * 105.0 + (52.0 if row % 2 == 1 else 0.0)
					var hcy := 70.0 + float(row) * 125.0
					var pts := PackedVector2Array()
					for i in 7:
						var a := PI / 6.0 + float(i) * PI / 3.0
						pts.append(Vector2(hcx, hcy) + Vector2(cos(a), sin(a)) * 38.0)
					draw_polyline(pts, hex_col, 1.5)
			for b in 2:
				var bx := 207.0 + sin(ht * (0.5 + float(b) * 0.2) + float(b) * 3.0) * 160.0
				var by := 300.0 + float(b) * 280.0 + cos(ht * 0.7 + float(b)) * 90.0
				draw_circle(Vector2(bx, by), 5.0, Color(1.0, 0.85, 0.25, 0.15))
				draw_line(Vector2(bx - 4, by), Vector2(bx + 4, by), Color(0.1, 0.08, 0.02, 0.18), 2.0)
				var wf := absf(sin(ht * 14.0 + float(b)))
				draw_circle(Vector2(bx, by - 5.0 - wf * 2.0), 3.0, Color(1, 1, 1, 0.10))
		13:  # Arcade — coarse pixel grid + floating pixel pluses
			for gx2 in range(0, 414, 32):
				draw_line(Vector2(gx2, 0), Vector2(gx2, 896), Color(0.40, 1.0, 0.90, 0.030), 1.0)
			for gy2 in range(0, 896, 32):
				draw_line(Vector2(0, gy2), Vector2(414, gy2), Color(0.40, 1.0, 0.90, 0.030), 1.0)
			var at := Time.get_ticks_msec() * 0.001
			for i in 6:
				var px2 : float = fmod(float(i * 131 + 37) * 31.7, 414.0)
				var py2 : float = fmod(float(i * 89 + 17) * 47.3 - at * (8.0 + float(i % 3) * 4.0), 896.0)
				if py2 < 0.0: py2 += 896.0
				var ps := 7.0
				var pc := Color(0.40, 1.0, 0.90, 0.06) if i % 2 == 0 else Color(1.0, 0.45, 0.85, 0.06)
				draw_rect(Rect2(px2 - ps * 0.5, py2 - ps * 1.5, ps, ps * 3.0), pc, true)
				draw_rect(Rect2(px2 - ps * 1.5, py2 - ps * 0.5, ps * 3.0, ps), pc, true)
		14:  # Bubble Bath — bubbles of all sizes rising
			var bt2 := Time.get_ticks_msec() * 0.001
			for i in 14:
				var bx2 : float = fmod(float(i * 131 + 31) * 23.9 + sin(bt2 * 0.6 + float(i)) * 18.0, 414.0)
				var by2 : float = fmod(float(i * 73 + 7) * 41.3 - bt2 * (14.0 + float(i % 5) * 7.0), 896.0)
				if by2 < 0.0: by2 += 896.0
				var br2 := 8.0 + float(i % 4) * 9.0
				draw_arc(Vector2(bx2, by2), br2, 0, TAU, 20, Color(1, 1, 1, 0.08), 1.5, false)
				draw_circle(Vector2(bx2 - br2 * 0.35, by2 - br2 * 0.35), br2 * 0.18, Color(1, 1, 1, 0.08))
		15:  # Thunderstorm — driving rain + cloud bank + lightning flashes
			var tt := Time.get_ticks_msec() * 0.001
			for i in 3:
				draw_circle(Vector2(70.0 + float(i) * 140.0, 40.0 + float(i % 2) * 22.0), 55.0,
					Color(0.60, 0.70, 0.90, 0.05))
			for i in 22:
				var rx2 : float = fmod(float(i * 97 + 13) * 37.3 - tt * 30.0, 414.0)
				if rx2 < 0.0: rx2 += 414.0
				var ry2 : float = fmod(float(i * 53 + 71) * 19.7 + tt * (180.0 + float(i % 5) * 40.0), 896.0)
				draw_line(Vector2(rx2, ry2), Vector2(rx2 - 6.0, ry2 + 16.0), Color(0.70, 0.80, 1.0, 0.08), 1.3)
			var lf := fmod(tt, 6.0)
			if lf < 0.18:
				var fl := 1.0 - lf / 0.18
				draw_rect(Rect2(Vector2.ZERO, Vector2(414, 896)), Color(1, 1, 1, 0.05 * fl), true)
				draw_polyline(PackedVector2Array([Vector2(290, 0), Vector2(255, 160), Vector2(285, 185), Vector2(240, 360)]),
					Color(1.0, 1.0, 0.80, 0.20 * fl), 2.5)
		16:  # Blossom — drifting petals + blossom branch
			var pt2 := Time.get_ticks_msec() * 0.001
			var br3 := Color(0.30, 0.18, 0.14, 0.25)
			draw_line(Vector2(414, 70), Vector2(250, 130), br3, 4.0)
			draw_line(Vector2(310, 108), Vector2(280, 60), br3, 2.5)
			for i in 4:
				draw_circle(Vector2(280.0 + float(i) * 32.0, 70.0 + float(i % 2) * 38.0), 7.0,
					Color(1.0, 0.78, 0.85, 0.12))
			for i in 10:
				var px3 : float = fmod(float(i * 131 + 31) * 23.9 + sin(pt2 * 0.8 + float(i)) * 26.0, 414.0)
				var py3 : float = fmod(float(i * 73 + 7) * 41.3 + pt2 * (12.0 + float(i % 4) * 6.0), 896.0)
				var rot2 := pt2 * 0.8 + float(i) * 1.3
				draw_set_transform(Vector2(px3, py3), rot2)
				draw_polygon(PackedVector2Array([Vector2(0, -5), Vector2(3.5, 0), Vector2(0, 5), Vector2(-3.5, 0)]),
					PackedColorArray([Color(1.0, 0.82, 0.88, 0.10)]))
				draw_set_transform(Vector2.ZERO)
		17:  # The Vault — coins flipping + sparkles
			var vt2 := Time.get_ticks_msec() * 0.001
			for i in 5:
				var cx2 : float = fmod(float(i * 113 + 29) * 37.1, 414.0)
				var cy2 : float = fmod(float(i * 67 + 43) * 45.9 - vt2 * (10.0 + float(i % 3) * 5.0), 896.0)
				if cy2 < 0.0: cy2 += 896.0
				var flip := sin(vt2 * 1.5 + float(i) * 1.7)
				draw_set_transform(Vector2(cx2, cy2), 0.0, Vector2(maxf(absf(flip), 0.12), 1.0))
				draw_arc(Vector2.ZERO, 13.0, 0, TAU, 20, Color(1.0, 0.85, 0.40, 0.10), 2.0, false)
				draw_arc(Vector2.ZERO, 8.0, 0, TAU, 16, Color(1.0, 0.85, 0.40, 0.07), 1.5, false)
				draw_set_transform(Vector2.ZERO)
			for i in 6:
				var sx3 : float = fmod(float(i * 97 + 13) * 41.3, 414.0)
				var sy3 : float = fmod(float(i * 53 + 71) * 23.7, 896.0)
				var tw2 : float = 0.05 + 0.10 * absf(sin(vt2 * 2.0 + float(i) * 1.4))
				draw_line(Vector2(sx3 - 5, sy3), Vector2(sx3 + 5, sy3), Color(1.0, 0.95, 0.6, tw2), 1.0)
				draw_line(Vector2(sx3, sy3 - 5), Vector2(sx3, sy3 + 5), Color(1.0, 0.95, 0.6, tw2), 1.0)
		18:  # Swamp — murk bands, rising goo bubbles, drips from above
			var wt2 := Time.get_ticks_msec() * 0.001
			for i in 4:
				draw_rect(Rect2(0, 650.0 + float(i) * 70.0, 414, 40), Color(0.30, 0.55, 0.20, 0.03 + float(i) * 0.012), true)
			for i in 10:
				var gx3 : float = fmod(float(i * 131 + 37) * 29.7 + sin(wt2 + float(i)) * 10.0, 414.0)
				var gy3 : float = fmod(float(i * 89 + 17) * 47.3 - wt2 * (10.0 + float(i % 4) * 5.0), 896.0)
				if gy3 < 0.0: gy3 += 896.0
				draw_arc(Vector2(gx3, gy3), 4.0 + float(i % 3) * 3.0, 0, TAU, 12, Color(0.55, 0.95, 0.35, 0.08), 1.5, false)
			for i in 3:
				var dx2 := 80.0 + float(i) * 130.0
				var dk2 := fmod(wt2 * 0.30 + float(i) * 0.37, 1.0)
				# Ooze down, then retract — no sudden vanish
				var dkk := (dk2 / 0.6) if dk2 < 0.6 else (1.0 - (dk2 - 0.6) / 0.4)
				if dkk > 0.02:
					var dl := 60.0 * dkk
					draw_line(Vector2(dx2, 0), Vector2(dx2, dl), Color(0.45, 0.85, 0.30, 0.10), 4.0 * (0.55 + 0.45 * dkk))
					draw_circle(Vector2(dx2, dl), 4.0 * (0.55 + 0.45 * dkk), Color(0.55, 0.95, 0.35, 0.12))
		19:  # Dance Floor — pulsing checkerboard + sweeping light beams
			var dt2 := Time.get_ticks_msec() * 0.001
			var tile := 59.0
			for ty in 3:
				for tx in 7:
					var hue2 := fmod(float(tx + ty) * 0.09 + dt2 * 0.10, 1.0)
					var pulse2 := 0.04 + 0.05 * absf(sin(dt2 * 1.6 + float(tx * 3 + ty) * 1.1))
					draw_rect(Rect2(float(tx) * tile, 720.0 + float(ty) * tile, tile - 2.0, tile - 2.0),
						Color.from_hsv(hue2, 0.6, 1.0, pulse2), true)
			for i in 3:
				var ba := PI * 0.5 + sin(dt2 * 0.7 + float(i) * 2.1) * 0.6
				var origin := Vector2(70.0 + float(i) * 137.0, 0.0)
				var tip2 := origin + Vector2(cos(ba), sin(ba)) * 700.0
				var hue3 := fmod(float(i) * 0.30 + dt2 * 0.08, 1.0)
				draw_polygon(PackedVector2Array([origin, tip2 + Vector2(-40, 0), tip2 + Vector2(40, 0)]),
					PackedColorArray([Color.from_hsv(hue3, 0.5, 1.0, 0.05)]))
		20:  # Aurora Sky — twinkling stars + flowing light curtains
			var at := Time.get_ticks_msec() * 0.001
			for i in 22:
				var stx : float = fmod(float(i * 131 + 23) * 17.3, 414.0)
				var sty : float = fmod(float(i * 89 + 11) * 23.7, 896.0)
				var tw : float = 0.4 + 0.6 * absf(sin(at * 1.5 + float(i)))
				draw_circle(Vector2(stx, sty), 1.5, Color(1, 1, 1, 0.20 * tw))
			for band in 3:
				var hue : float = fmod(0.34 + float(band) * 0.10 + 0.04 * sin(at * 0.3), 1.0)
				var ac := Color.from_hsv(hue, 0.6, 1.0, 0.06)
				var top := PackedVector2Array()
				var by : float = 200.0 + float(band) * 180.0
				for k in 11:
					var x : float = float(k) / 10.0 * 414.0
					var y : float = by + sin(at * 0.8 + float(k) * 0.5 + float(band) * 1.3) * 60.0
					top.append(Vector2(x, y))
				var ribbon := top.duplicate()
				for k in range(10, -1, -1):
					ribbon.append(Vector2(top[k].x, top[k].y + 130.0))
				draw_polygon(ribbon, PackedColorArray([ac]))
		21:  # Plasma Field — floating, pulsing energy orbs
			var pt := Time.get_ticks_msec() * 0.001
			for i in 5:
				var ox : float = 80.0 + float(i) * 75.0 + sin(pt * 0.4 + float(i)) * 30.0
				var oy : float = 150.0 + float(i) * 150.0 + cos(pt * 0.5 + float(i) * 1.3) * 40.0
				var pls : float = 0.5 + 0.5 * sin(pt * 2.0 + float(i))
				draw_circle(Vector2(ox, oy), 30.0 + pls * 12.0, Color(0.7, 0.4, 1.0, 0.05))
				draw_circle(Vector2(ox, oy), 11.0, Color(0.85, 0.6, 1.0, 0.07))
		22:  # Opal — soft iridescent colour clouds drifting
			var dt22 := Time.get_ticks_msec() * 0.001
			for i in 6:
				var ox : float = 70.0 + float(i) * 60.0
				var oy : float = 170.0 + float(i) * 110.0 + sin(dt22 * 0.4 + float(i) * 1.4) * 45.0
				var oh : float = fmod(float(i) * 0.17 + dt22 * 0.04, 1.0)
				var oc := Color.from_hsv(oh, 0.45, 1.0)
				draw_circle(Vector2(ox, oy), 70.0, Color(oc.r, oc.g, oc.b, 0.045))
				draw_circle(Vector2(ox, oy), 24.0, Color(oc.r, oc.g, oc.b, 0.05))
		23:  # Data Stream — falling green code columns
			var dt3 := Time.get_ticks_msec() * 0.001
			for c in 12:
				var cx : float = 18.0 + float(c) * 34.0
				var spd : float = 120.0 + float((c * 37) % 5) * 50.0
				var head : float = fmod(dt3 * spd + float(c * 91), 1000.0)
				for k in 8:
					var gy : float = head - float(k) * 22.0
					if gy < 0.0 or gy > 896.0:
						continue
					var a : float = (1.0 - float(k) / 8.0) * 0.10
					draw_rect(Rect2(cx, gy, 7.0, 12.0), Color(0.3, 1.0, 0.45, a), true)
		24:  # Holo Deck — rolling scanlines + floating wireframe boxes
			var ht := Time.get_ticks_msec() * 0.001
			var hoff := fmod(ht * 30.0, 28.0)
			for yy in range(int(hoff) - 28, 896, 28):
				draw_line(Vector2(0, float(yy)), Vector2(414, float(yy)), Color(0.5, 0.9, 1.0, 0.04), 1.0)
			for i in 3:
				var wx : float = 100.0 + float(i) * 110.0 + sin(ht * 0.4 + float(i)) * 20.0
				var wy : float = 200.0 + float(i) * 230.0 + cos(ht * 0.5 + float(i)) * 30.0
				var sz := 26.0
				var hue : float = fmod(0.5 + float(i) * 0.1 + ht * 0.05, 1.0)
				var wc := Color.from_hsv(hue, 0.5, 1.0, 0.06)
				draw_rect(Rect2(wx - sz, wy - sz, sz * 2.0, sz * 2.0), wc, false, 1.5)
				draw_rect(Rect2(wx - sz + 9.0, wy - sz - 9.0, sz * 2.0, sz * 2.0), wc, false, 1.5)
				draw_line(Vector2(wx - sz, wy - sz), Vector2(wx - sz + 9.0, wy - sz - 9.0), wc, 1.0)
				draw_line(Vector2(wx + sz, wy + sz), Vector2(wx + sz + 9.0, wy + sz - 9.0), wc, 1.0)
		25:  # Prism — soft drifting rainbow light bands
			var prt := Time.get_ticks_msec() * 0.001
			for i in 5:
				var hue : float = fmod(0.12 * float(i) + prt * 0.05, 1.0)
				var pc := Color.from_hsv(hue, 0.6, 1.0, 0.05)
				var by : float = fmod(float(i) * 200.0 + prt * 18.0, 1000.0) - 60.0
				draw_rect(Rect2(0, by, 414, 70), pc, true)
		26:  # Cathedral — soft coloured light shafts from above
			var cat_t := Time.get_ticks_msec() * 0.001
			for i in 5:
				var lx : float = 40.0 + float(i) * 84.0
				var hue : float = fmod(0.16 * float(i) + 0.4, 1.0)
				var sc := Color.from_hsv(hue, 0.55, 1.0, 0.05 + 0.02 * sin(cat_t * 0.5 + float(i)))
				draw_polygon(PackedVector2Array([
					Vector2(lx, 0), Vector2(lx + 60.0, 0),
					Vector2(lx + 130.0, 896.0), Vector2(lx + 10.0, 896.0)]),
					PackedColorArray([sc]))
		27:  # Outrun — neon perspective grid + sun
			var ot := Time.get_ticks_msec() * 0.001
			var horizon := 470.0
			draw_circle(Vector2(207, horizon - 40.0), 110.0, Color(1.0, 0.35, 0.55, 0.07))
			var ng := Color(0.45, 1.0, 0.95, 0.06)
			for i in 9:
				var gx : float = float(i) / 8.0 * 414.0
				draw_line(Vector2(gx, horizon), Vector2((gx - 207.0) * 3.0 + 207.0, 896.0), ng, 1.5)
			for i in 7:
				var f : float = fmod(float(i) / 7.0 + ot * 0.12, 1.0)
				var gy : float = horizon + f * f * (896.0 - horizon)
				draw_line(Vector2(0, gy), Vector2(414, gy), ng, 1.5)
		28:  # Harvest — drifting autumn leaves
			var at2 := Time.get_ticks_msec() * 0.001
			var lcs : Array = [Color(0.85, 0.28, 0.12, 0.10), Color(0.95, 0.55, 0.15, 0.10), Color(0.92, 0.76, 0.25, 0.10)]
			for i in 14:
				var lx2 : float = fmod(float(i * 137 + 30) * 11.0 + sin(at2 * 0.5 + float(i)) * 30.0, 414.0)
				var ly : float = fmod(float(i * 83 + 12) * 19.0 + at2 * (28.0 + float(i % 4) * 8.0), 960.0) - 30.0
				draw_circle(Vector2(lx2, ly), 5.0 + float(i % 3) * 2.0, lcs[i % lcs.size()])
		29:  # Hyperspace — stars streaking from the centre
			var wt := Time.get_ticks_msec() * 0.001
			var wc := Vector2(207, 430)
			for i in 26:
				var ang : float = float(i) / 26.0 * TAU + float(i % 5) * 0.1
				var dirv := Vector2(cos(ang), sin(ang))
				var ph : float = fmod(wt * 0.5 + float(i) * 0.07, 1.0)
				var d0 : float = ph * 520.0
				var sp := wc + dirv * d0
				var tail := wc + dirv * maxf(d0 - 40.0 - ph * 90.0, 0.0)
				draw_line(tail, sp, Color(0.7, 0.85, 1.0, ph * 0.18), 1.0 + ph * 1.5)
		30:  # Meow Town — drifting paw prints, floating yarn + fish
			var mt3 := Time.get_ticks_msec() * 0.001
			var paw := Color(1.0, 0.80, 0.88, 0.07)
			for i in 9:
				var pxp : float = fmod(float(i * 131 + 37) * 29.7, 414.0)
				var pyp : float = fmod(float(i * 89 + 17) * 47.3 - mt3 * (7.0 + float(i % 4) * 3.0), 940.0) - 22.0
				if pyp < -22.0: pyp += 940.0
				# paw: main pad + 4 toe beans
				draw_circle(Vector2(pxp, pyp), 7.0, paw)
				for j in 4:
					var a := -PI * 0.5 + (float(j) - 1.5) * 0.5
					draw_circle(Vector2(pxp, pyp) + Vector2(cos(a), sin(a)) * 11.0, 3.2, paw)
			# A couple of yarn balls slowly spinning
			for i in 2:
				var yx := 90.0 + float(i) * 230.0
				var yy := 230.0 + float(i) * 360.0 + sin(mt3 * 0.5 + float(i)) * 30.0
				draw_circle(Vector2(yx, yy), 24.0, Color(1.0, 0.70, 0.80, 0.06))
				for k in 4:
					var ra := mt3 * 0.4 + float(k) * 0.8 + float(i)
					draw_arc(Vector2(yx, yy), 24.0 - float(k) * 5.0, ra, ra + PI * 1.4, 20,
						Color(1.0, 0.78, 0.86, 0.07), 1.5, false)
			# Little fish swimming across
			for i in 3:
				var flip := 1.0 if i % 2 == 0 else -1.0
				var fxp : float = fmod(mt3 * (22.0 + float(i) * 8.0) + float(i * 157), 514.0) - 50.0
				if flip < 0.0: fxp = 414.0 - fxp
				var fyp : float = 140.0 + float(i) * 250.0 + sin(mt3 * 1.4 + float(i)) * 14.0
				var fc := Color(1.0, 0.85, 0.90, 0.07)
				draw_set_transform(Vector2(fxp, fyp), 0.0, Vector2(flip, 1.0))
				draw_circle(Vector2.ZERO, 8.0, fc)
				draw_polygon(PackedVector2Array([Vector2(-7, 0), Vector2(-15, -6), Vector2(-15, 6)]),
					PackedColorArray([fc]))
				draw_set_transform(Vector2.ZERO)

func _draw_slot(i: int) -> void:
	var sx   : float = i * SLOT_W
	var rect := Rect2(sx + 6, TRAY_Y + 8, SLOT_W - 12, TRAY_H - 16)
	# Spawn bounce: cards puff up briefly when a fresh set arrives (staggered)
	if tray_pop_t > 0.0:
		var lt := clampf(tray_pop_t + float(i) * 0.12, 0.0, 1.0)
		rect = rect.grow(sin(lt * PI) * 5.0)
	var bg   : Color = Color(0.18, 0.14, 0.24) if dragging_slot == i else Color(0.11, 0.09, 0.16)
	_rr_fill(Rect2(rect.position + Vector2(0, 3), rect.size), 16.0, Color(0, 0, 0, 0.30))
	_rr_fill(rect, 16.0, bg)
	_rr_outline(rect, 16.0, Color(1, 1, 1, 0.07), 1.5)

	# Leave the source slot empty while dragging — no faint silhouette behind it
	if placed[i] or dragging_slot == i:
		return

	var shape : Array = pieces[i].shape
	var color : Color = pieces[i].color

	var min_c := 99; var max_c := 0
	var min_r := 99; var max_r := 0
	for cell in shape:
		if (cell[0] as int) < min_c: min_c = cell[0]
		if (cell[0] as int) > max_c: max_c = cell[0]
		if (cell[1] as int) < min_r: min_r = cell[1]
		if (cell[1] as int) > max_r: max_r = cell[1]

	var pw : float = (max_c - min_c + 1) * TRAY_STEP - 1.0
	var ph : float = (max_r - min_r + 1) * TRAY_STEP - 1.0
	var avail_w : float = SLOT_W - 12.0
	var scale_f : float = minf(1.0, minf(avail_w / pw, TRAY_H / ph))
	var tcell   : float = TRAY_CELL * scale_f
	var tstep   : float = TRAY_STEP * scale_f
	var pw_s    : float = pw * scale_f
	var ph_s    : float = ph * scale_f
	var ox : float = sx + 6.0 + (avail_w - pw_s) * 0.5 - min_c * tstep
	var oy : float = TRAY_Y + (TRAY_H - ph_s) * 0.5 - min_r * tstep

	# Spawn grow+bounce: each fresh piece scales up from a point with an overshoot,
	# staggered slot-to-slot, instead of teleporting in at full size.
	var pop_s := 1.0
	if tray_pop_t > 0.0:
		var ap := clampf((1.0 - tray_pop_t) * 1.6 - float(i) * 0.16, 0.0, 1.0)
		pop_s = _back_out(ap)
	var pcx : float = ox + min_c * tstep + pw_s * 0.5   # piece centre (scale origin)
	var pcy : float = oy + min_r * tstep + ph_s * 0.5

	for cell in shape:
		var rx : float = ox + cell[0] * tstep
		var ry : float = oy + cell[1] * tstep
		var cr := Rect2(rx, ry, tcell, tcell)
		if pop_s != 1.0:
			var ncell : float = tcell * pop_s
			if ncell < 6.0:
				continue   # too small to paint cleanly — skip this first instant
			var ccx : float = pcx + (rx + tcell * 0.5 - pcx) * pop_s
			var ccy : float = pcy + (ry + tcell * 0.5 - pcy) * pop_s
			cr = Rect2(ccx - ncell * 0.5, ccy - ncell * 0.5, ncell, ncell)
		_draw_styled_block(cr, color,
			pieces[i].get("pattern", 0) + cell[0] * 7 + cell[1] * 13)

# Draws on drag_layer (above the grid) — the piece floats DRAG_LIFT px above
# the finger so it's never hidden under the player's hand
func _draw_drag_layer() -> void:
	if dragging_slot < 0 or placed[dragging_slot]:
		return
	var lifted := drag_pos + Vector2(0, -DRAG_LIFT)
	var shape : Array    = pieces[dragging_slot].shape
	var color : Color    = pieces[dragging_slot].color

	# The dragged piece ALWAYS follows the finger freely (never grid-snaps) — the
	# snappy board ghost is the precise "this is where it lands" shadow instead.
	var min_c := 99; var max_c := 0; var min_r := 99; var max_r := 0
	for cell in shape:
		if (cell[0] as int) < min_c: min_c = cell[0]
		if (cell[0] as int) > max_c: max_c = cell[0]
		if (cell[1] as int) < min_r: min_r = cell[1]
		if (cell[1] as int) > max_r: max_r = cell[1]
	var ox : float = lifted.x - (max_c - min_c + 1) * GRID_STEP * 0.5 - min_c * GRID_STEP
	var oy : float = lifted.y - (max_r - min_r + 1) * GRID_STEP * 0.5 - min_r * GRID_STEP

	var draw_color : Color = color

	# Pickup pop: piece jumps bigger the instant it's grabbed, then springs back.
	# (drag_pop_t starts at 1.0 on grab and decays — so the pop is biggest at pickup.)
	var pop := 1.0 + drag_pop_t * 0.20
	var pat : int = pieces[dragging_slot].get("pattern", 0)
	for cell in shape:
		var rx : float = ox + cell[0] * GRID_STEP
		var ry : float = oy + cell[1] * GRID_STEP
		var cr := Rect2(rx, ry, CELL, CELL)
		if pop > 1.001:
			cr = cr.grow(CELL * (pop - 1.0) * 0.5)
		# Pattern sampled in BOARD space (grid-local coords) so continuous
		# skins show, while hovering, exactly the pattern that will land
		var pat_r := Rect2(Vector2(rx - GRID_X, ry - GRID_Y), Vector2(CELL, CELL))
		BlockSkins.paint(drag_layer, grid.block_style, cr, draw_color,
			pat + cell[0] * 7 + cell[1] * 13, 0.0, pat_r)

# ── Rounded drawing helpers (Game.gd copy of Grid.gd's) ──────────────────────
# Reuse BlockSkins' precomputed 16 corner unit-directions so this is pure
# add/multiply (no per-call cos/sin) — the UI chrome redraws every main-canvas
# frame (the animated background keeps it at 30fps), so it adds up.
# Round every corner of an arbitrary polygon with a quadratic-bezier fillet — used
# for the cute bubbly rescue arrow (one smooth outline around the whole silhouette).
func _round_poly(pts: PackedVector2Array, radius: float, segs: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var cur := pts[i]
		var din := cur - pts[(i - 1 + n) % n]
		var dout := pts[(i + 1) % n] - cur
		var lin := din.length()
		var lout := dout.length()
		if lin < 0.001 or lout < 0.001:
			out.append(cur)
			continue
		din /= lin
		dout /= lout
		var r := minf(radius, minf(lin, lout) * 0.5)
		var a := cur - din * r
		var b := cur + dout * r
		for s in segs + 1:
			var t := float(s) / float(segs)
			var omt := 1.0 - t
			out.append(a * (omt * omt) + cur * (2.0 * omt * t) + b * (t * t))
	return out

func _rr_points(r: Rect2, rad: float) -> PackedVector2Array:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	var c0 := Vector2(r.position.x + rad, r.position.y + rad)
	var c1 := Vector2(r.end.x - rad,      r.position.y + rad)
	var c2 := Vector2(r.end.x - rad,      r.end.y - rad)
	var c3 := Vector2(r.position.x + rad, r.end.y - rad)
	var pts := PackedVector2Array()
	pts.resize(16)
	for i in 4:
		pts[i]      = c0 + BlockSkins._RR_UNIT[i] * rad
		pts[4 + i]  = c1 + BlockSkins._RR_UNIT[4 + i] * rad
		pts[8 + i]  = c2 + BlockSkins._RR_UNIT[8 + i] * rad
		pts[12 + i] = c3 + BlockSkins._RR_UNIT[12 + i] * rad
	return pts

func _rr_fill(r: Rect2, rad: float, col: Color) -> void:
	draw_polygon(_rr_points(r, rad), PackedColorArray([col]))

func _rr_outline(r: Rect2, rad: float, col: Color, width: float) -> void:
	var pts := _rr_points(r, rad)
	pts.append(pts[0])
	draw_polyline(pts, col, width)

func _rr_grad(r: Rect2, rad: float, top_col: Color, bot_col: Color) -> void:
	var pts := _rr_points(r, rad)
	var n := pts.size()
	if _ui_gradbuf.size() != n:
		_ui_gradbuf.resize(n)
	var inv_h := 1.0 / r.size.y
	for i in n:
		_ui_gradbuf[i] = top_col.lerp(bot_col, clampf((pts[i].y - r.position.y) * inv_h, 0.0, 1.0))
	draw_polygon(pts, _ui_gradbuf)

func _draw_gear_button() -> void:
	var c := GEAR_RECT.get_center()
	var acc : Color = THEMES[_visual_idx()]["accent"]
	# Chunky candy chip: soft bottom ledge, dark face with a faint biome tint, an
	# accent rim, and a crisp white gear with a hollow centre.
	_rr_fill(Rect2(GEAR_RECT.position + Vector2(0, 3), GEAR_RECT.size), 13.0, Color(0, 0, 0, 0.35))
	_rr_fill(GEAR_RECT, 13.0, Color(0.12, 0.10, 0.17, 0.92))
	_rr_fill(GEAR_RECT, 13.0, Color(acc.r, acc.g, acc.b, 0.12))
	_rr_outline(GEAR_RECT, 13.0, Color(acc.r, acc.g, acc.b, 0.60), 1.5)
	var gear_col := Color(1, 1, 1, 0.92)
	for i in 8:
		var a := float(i) / 8.0 * TAU
		draw_line(c + Vector2(cos(a), sin(a)) * 8.5, c + Vector2(cos(a), sin(a)) * 12.5, gear_col, 3.2)
	draw_arc(c, 8.5, 0, TAU, 28, gear_col, 3.2, false)
	draw_circle(c, 3.4, gear_col)
	draw_circle(c, 2.0, Color(0.12, 0.10, 0.17, 1.0))

# ── Power orb (charge meter + spend button) ──────────────────────────────────
func _power_tier() -> int:
	if meter >= METER_FULL:    return 3
	elif meter >= METER_LASER: return 2
	elif meter >= METER_BOMB:  return 1
	return 0

func _draw_power_orb() -> void:
	var c := POWER_CENTER
	var usable := meter >= METER_BOMB
	var tier := _power_tier()
	var tcol : Color
	match tier:
		3: tcol = Color(1.0, 0.85, 0.30)
		2: tcol = Color(1.0, 0.42, 0.28)
		1: tcol = Color(1.0, 0.58, 0.20)
		_: tcol = Color(0.55, 0.55, 0.68)
	# Pulse gets faster + stronger the higher the tier, to pull the eye
	var pulse := (sin(Time.get_ticks_msec() * (0.005 + float(tier) * 0.004)) + 1.0) * 0.5
	# Ready glow — escalates bomb → laser → ultimate
	if usable:
		var base_glow := 0.12 + float(tier) * 0.09
		var ga := base_glow * (0.45 + 0.55 * pulse) + power_pulse * 0.55
		draw_circle(c, POWER_R + 8.0 + pulse * (3.0 + float(tier) * 3.0),
			Color(tcol.r, tcol.g, tcol.b, ga))
		# Extra halo for laser, a sparkling ring for the ultimate
		if tier >= 2:
			draw_circle(c, POWER_R + 15.0 + pulse * 6.0, Color(tcol.r, tcol.g, tcol.b, 0.12 * pulse))
		if tier >= 3:
			draw_arc(c, POWER_R + 19.0 + pulse * 3.0, 0, TAU, 36, Color(1, 1, 1, 0.30 * pulse), 2.0, true)
	# Base disc
	draw_circle(c, POWER_R, Color(0.08, 0.07, 0.13, 0.92))
	# Meter track + fill
	draw_arc(c, POWER_R - 5.0, 0, TAU, 40, Color(1, 1, 1, 0.08), 4.0, true)
	if meter > 0.001:
		var start := -PI * 0.5
		draw_arc(c, POWER_R - 5.0, start, start + TAU * meter, 48, tcol, 4.0, true)
	# Tier ticks at ¼ and ½
	for frac : float in [0.25, 0.5]:
		var a : float = -PI * 0.5 + TAU * frac
		var dir := Vector2(cos(a), sin(a))
		draw_line(c + dir * (POWER_R - 9.0), c + dir * (POWER_R - 1.0), Color(1, 1, 1, 0.5), 1.5)
	# Rim
	draw_arc(c, POWER_R, 0, TAU, 40, Color(tcol.r, tcol.g, tcol.b, 0.6 if usable else 0.25), 2.0, true)
	# Icon for the ability the meter currently affords
	# Icon flashes harder the higher the tier (plus the one-shot tier-up flash)
	var icon_pulse : float = clampf(pulse * (1.0 + float(tier) * 0.4) + power_pulse * 0.6, 0.0, 1.6)
	_draw_power_icon(c, tier, Color(1, 1, 1, 0.92) if usable else Color(1, 1, 1, 0.35), icon_pulse)

func _draw_power_icon(c: Vector2, tier: int, icol: Color, pulse: float) -> void:
	match tier:
		3:
			# Gravity ult: four arrows converging on a bright core
			for i in 4:
				var a : float = float(i) / 4.0 * TAU + PI * 0.25
				var dir := Vector2(cos(a), sin(a))
				var perp := Vector2(-dir.y, dir.x)
				draw_line(c + dir * 10.0, c + dir * 4.0, Color(1.0, 0.9, 0.5), 2.5)
				draw_line(c + dir * 4.0, c + dir * 6.5 + perp * 2.6, Color(1.0, 0.9, 0.5), 2.0)
				draw_line(c + dir * 4.0, c + dir * 6.5 - perp * 2.6, Color(1.0, 0.9, 0.5), 2.0)
			draw_circle(c, 2.6 + pulse * 1.6, Color(1, 1, 1, 0.95))
		2:
			# Twin bomb: one bomb (like tier 1) + a "×2" badge — reads instantly
			var bp := c + Vector2(-5.0, 2.5)
			draw_circle(bp, 7.0, Color(0.10, 0.10, 0.15))
			draw_arc(bp, 7.0, 0, TAU, 18, icol, 2.0, true)
			draw_circle(bp + Vector2(-2.2, -0.5), 1.5, Color(icol.r, icol.g, icol.b, 0.6))
			draw_line(bp + Vector2(3.4, -4.2), bp + Vector2(5.6, -8.8), icol, 1.8)
			draw_circle(bp + Vector2(5.6, -8.8), 1.8 + 0.4 * pulse, Color(1.0, 0.8, 0.3, 0.55 + 0.35 * pulse))
			if _icon_font:
				draw_string(_icon_font, c + Vector2(3.5, 7.0), "×2",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, icol)
		_:
			# Bomb (tier 0 dim, tier 1 lit): round body, fuse + spark
			draw_circle(c + Vector2(0, 2), 8.0, Color(0.10, 0.10, 0.15))
			draw_arc(c + Vector2(0, 2), 8.0, 0, TAU, 20, icol, 2.0, true)
			draw_circle(c + Vector2(-2.6, -0.6), 1.8, Color(icol.r, icol.g, icol.b, 0.6))
			draw_line(c + Vector2(4, -5), c + Vector2(7, -11), icol, 2.0)
			draw_circle(c + Vector2(7, -11), 2.0 + 0.5 * pulse, Color(1.0, 0.8, 0.3, 0.55 + 0.35 * pulse))

# ── Power FX (drawn on the top fx_layer, screen coords) ──────────────────────
func _draw_fx_layer() -> void:
	for e in effects:
		var p : float = clampf(e["t"] / e["dur"], 0.0, 1.0)
		match e["type"]:
			"bomb_drop":    _fx_bomb_drop(e, p)
			"bomb_blast":   _fx_bomb_blast(e, p)
			"laser_charge": _fx_laser_charge(e, p)
			"laser_fire":   _fx_laser_fire(e, p)
			"gravity":      _fx_gravity(e, p)
			"pixel_art":    _fx_pixel_art(e, p)
			"sparkle":      _fx_sparkle_burst(e, p)
	# Drawn here (top layer) so it sits ABOVE the board cells; Game._draw is behind them.
	if rescue_active:
		_draw_rescue(fx_layer)

# Board-clear flourish: the WHOLE board fills with a colourful pixel pattern made
# of the CURRENT skin's own blocks (every skin gets it for free), held a beat,
# then popped away — under 2s. Every pattern covers all 64 cells and uses as many
# of the 6 palette colours as it can.
const PIXEL_PATTERNS := 6

# Colour index 0-5 for cell (r,c) under pattern `pat` — always a real colour, so
# the board is always fully covered.
func _pixel_color(pat: int, r: int, c: int) -> int:
	match pat:
		0: return (r + c) % 6                          # diagonal rainbow
		1: return ((c - r) % 6 + 6) % 6                # anti-diagonal rainbow
		2: return r % 6                                # horizontal bands
		3: return c % 6                                # vertical bands
		4: return (int(r / 2.0) + int(c / 2.0)) % 6    # 2x2 colour mosaic
		5:
			var rd : int = mini(absi(r - 3), absi(r - 4))
			var cd : int = mini(absi(c - 3), absi(c - 4))
			return (rd + cd) % 6                        # diamond rings from centre
	return (r + c) % 6

func _trigger_board_clear_fx() -> void:
	effects.append({"type": "pixel_art", "t": 0.0, "dur": 1.2,
		"pattern": randi() % PIXEL_PATTERNS, "seed": randi() % 100000})
	fx_layer.queue_redraw()
	# POP: a screen punch once the picture finishes blooming (no white flash)
	await get_tree().create_timer(0.24).timeout
	shake_t = maxf(shake_t, 0.30)
	_buzz(55)

# Back-ease-out with extra overshoot for a punchy pop
func _back_out(x: float) -> float:
	var c1 := 2.2
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)

func _fx_pixel_art(e: Dictionary, p: float) -> void:
	var pat : int = e["pattern"]
	var base_seed : int = e["seed"]
	for r in GRID_ROWS:
		for c in GRID_COLS:
			# Bloom out from the board centre, brief hold, then fade + pop away early
			var dist : float = Vector2(float(c) - 3.5, float(r) - 3.5).length()
			var s : float
			var a : float = 1.0
			if p < 0.42:
				var lp : float = clampf((p - dist * 0.020) / 0.22, 0.0, 1.0)
				s = _back_out(lp)
			else:
				var op : float = clampf((p - 0.42) / 0.58, 0.0, 1.0)
				s = 1.0 - op * op
				a = 1.0 - op            # fade out as it shrinks
			var sz : float = CELL * s
			if sz < 6.0:
				continue
			var col : Color = COLORS[_pixel_color(pat, r, c)]
			col.a = a
			var cxp : float = GRID_X + float(c) * GRID_STEP + CELL * 0.5
			var cyp : float = GRID_Y + float(r) * GRID_STEP + CELL * 0.5
			var rect := Rect2(cxp - sz * 0.5, cyp - sz * 0.5, sz, sz)
			BlockSkins.paint(fx_layer, grid.block_style, rect, col,
				base_seed + r * 7 + c * 13, 0.0, rect, false)

func _fx_sparkle(pos: Vector2, size: float, col: Color) -> void:
	fx_layer.draw_line(pos + Vector2(-size, 0), pos + Vector2(size, 0), col, 1.5)
	fx_layer.draw_line(pos + Vector2(0, -size), pos + Vector2(0, size), col, 1.5)

# A quick burst of little rainbow 4-point stars that fly out and fade — the flashy
# pop on pickup and placement (Block-Blast-style sparkle).
func _spawn_sparkles(center: Vector2, n: int, spread: float) -> void:
	var parts : Array = []
	for i in n:
		parts.append({
			"ang":   randf() * TAU,
			"dist":  randf_range(spread * 0.35, spread),
			"size":  randf_range(4.0, 8.5),
			"hue":   randf(),
			"delay": randf() * 0.10,
		})
	effects.append({"type": "sparkle", "t": 0.0, "dur": 0.5, "center": center, "parts": parts})
	fx_layer.queue_redraw()

func _fx_sparkle_burst(e: Dictionary, p: float) -> void:
	var center : Vector2 = e["center"]
	for part in e["parts"]:
		var delay : float = part["delay"]
		var lp : float = clampf((p - delay) / maxf(1.0 - delay, 0.01), 0.0, 1.0)
		if lp <= 0.0:
			continue
		var d : float = float(part["dist"]) * (1.0 - pow(1.0 - lp, 2.0))   # ease-out fly-out
		var pos : Vector2 = center + Vector2(cos(part["ang"]), sin(part["ang"])) * d
		var sz : float = float(part["size"]) * sin(lp * PI)                # grow then shrink
		if sz < 0.6:
			continue
		var col := Color.from_hsv(fmod(float(part["hue"]) + p * 0.25, 1.0), 0.80, 1.0, 1.0 - lp * 0.5)
		_draw_star4(pos, sz, col)

# 4-point sparkle star (axis points long, diagonals short), drawn on fx_layer.
# Pops via a soft colour glow halo + a white-hot twinkle core (no dark outline —
# that swallowed the thin points and read as a black star at this size).
func _draw_star4(c: Vector2, r: float, col: Color) -> void:
	var a := col.a
	# Soft glow halo behind
	fx_layer.draw_circle(c, r * 1.8, Color(col.r, col.g, col.b, a * 0.18))
	fx_layer.draw_circle(c, r * 1.1, Color(col.r, col.g, col.b, a * 0.28))
	# The star itself, bright
	var inner : float = r * 0.36
	var pts := PackedVector2Array()
	for i in 4:
		var ang : float = float(i) * (PI * 0.5)
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)
		var ang2 : float = ang + PI * 0.25
		pts.append(c + Vector2(cos(ang2), sin(ang2)) * inner)
	BlockSkins.draw_poly_safe(fx_layer, pts, col)
	# White-hot twinkle core
	fx_layer.draw_circle(c, r * 0.30, Color(1, 1, 1, a * 0.9))

func _fx_bomb_drop(e: Dictionary, p: float) -> void:
	var target : Vector2 = e["pos"]
	var pos := (target + Vector2(0, -160)).lerp(target, p * p)   # accelerate down
	# growing shadow on the landing spot
	fx_layer.draw_circle(target + Vector2(0, 15), 6.0 + 10.0 * p, Color(0, 0, 0, 0.18 * p))
	# body + glint
	fx_layer.draw_circle(pos, 11.0, Color(0.10, 0.10, 0.15))
	fx_layer.draw_circle(pos + Vector2(-3, -3), 3.0, Color(1, 1, 1, 0.35))
	# fuse + flickering spark
	var tip := pos + Vector2(6, -13)
	fx_layer.draw_line(pos + Vector2(4, -8), tip, Color(0.82, 0.72, 0.5), 2.0)
	var sp := 2.0 + sin(e["t"] * 42.0) * 1.2
	fx_layer.draw_circle(tip, sp, Color(1.0, 0.85, 0.3, 0.9))
	fx_layer.draw_circle(tip, sp * 0.5, Color(1, 1, 1, 0.9))

func _fx_bomb_blast(e: Dictionary, p: float) -> void:
	var c : Vector2 = e["pos"]
	var eo := 1.0 - (1.0 - p) * (1.0 - p)   # ease-out
	# white-hot flash core
	if p < 0.4:
		var k := p / 0.4
		fx_layer.draw_circle(c, lerpf(8.0, 46.0, k), Color(1.0, 0.95, 0.7, (1.0 - k) * 0.9))
	# expanding shockwave rings
	for i in 3:
		var rp := clampf((p - float(i) * 0.08) / 0.6, 0.0, 1.0)
		if rp > 0.0 and rp < 1.0:
			fx_layer.draw_arc(c, lerpf(10.0, 95.0, rp), 0, TAU, 32,
				Color(1.0, 0.6, 0.2, (1.0 - rp) * 0.5), lerpf(5.0, 1.0, rp), true)
	# radial spark shards with trails
	for i in 12:
		var ang := float(i) / 12.0 * TAU + float((i * 7) % 5) * 0.1
		var dir := Vector2(cos(ang), sin(ang))
		var sp := c + dir * lerpf(6.0, 70.0 + float(i % 4) * 12.0, eo)
		var ssz := (1.0 - p) * (3.5 + float(i % 3))
		if ssz > 0.4:
			fx_layer.draw_line(sp, sp - dir * 8.0, Color(1.0, 0.7, 0.25, (1.0 - p) * 0.6), 2.0)
			fx_layer.draw_circle(sp, ssz, Color(1.0, 0.85, 0.4, 1.0 - p))
	# cute star sparkles
	for i in 3:
		var sa := float(i) / 3.0 * TAU + p * 2.0
		var spc := c + Vector2(cos(sa), sin(sa)) * lerpf(10.0, 55.0, p)
		var ss := (1.0 - p) * 5.0
		if ss > 0.5:
			_fx_sparkle(spc, ss, Color(1, 1, 1, 1.0 - p))
	# lingering smoke
	for i in 4:
		var sma := float(i) / 4.0 * TAU + 0.5
		fx_layer.draw_circle(c + Vector2(cos(sma), sin(sma)) * lerpf(0.0, 30.0, p),
			lerpf(4.0, 16.0, p), Color(0.5, 0.45, 0.45, (1.0 - p) * 0.18))
	# Debris chunks blown out then dragged down by gravity
	for i in 8:
		var da := float(i) / 8.0 * TAU + 0.3
		var out := Vector2(cos(da), -0.6 - float(i % 3) * 0.25) * (45.0 + float(i % 4) * 16.0)
		var dp := c + out * p + Vector2(0, 150.0 * p * p)   # parabolic fall
		var dsz := (1.0 - p * 0.7) * (5.0 + float(i % 3) * 2.0)
		if dsz > 1.0:
			var dcol := Color(1.0, 0.55, 0.20).lerp(Color(0.45, 0.28, 0.20), p)
			fx_layer.draw_rect(Rect2(dp - Vector2(dsz, dsz) * 0.5, Vector2(dsz, dsz)),
				Color(dcol.r, dcol.g, dcol.b, 1.0 - p), true)

func _fx_laser_charge(e: Dictionary, p: float) -> void:
	var path : PackedVector2Array = e["path"]
	var col : Color = e["color"]
	# gathering glow racing along the zig-zag
	for i in range(path.size() - 1):
		fx_layer.draw_line(path[i], path[i + 1], Color(col.r, col.g, col.b, 0.12 + 0.45 * p), 1.0 + 2.0 * p)
	# sparks converging onto each bounce point
	for i in path.size():
		fx_layer.draw_circle(path[i], 2.0 + 4.0 * p, Color(col.r, col.g, col.b, 0.35 * p))

func _fx_laser_fire(e: Dictionary, p: float) -> void:
	var path : PackedVector2Array = e["path"]
	var col : Color = e["color"]
	var fade := 1.0 - p
	# soft glow layers -> white-hot core, every segment of the bolt
	for layer : Array in [[20.0, 0.10], [12.0, 0.20], [6.0, 0.45]]:
		for i in range(path.size() - 1):
			fx_layer.draw_line(path[i], path[i + 1], Color(col.r, col.g, col.b, fade * float(layer[1])),
				float(layer[0]) * (0.6 + 0.4 * fade))
	for i in range(path.size() - 1):
		fx_layer.draw_line(path[i], path[i + 1], Color(1, 1, 1, fade), 3.0)
	# embers + flame licks flickering off each kink in the bolt
	for i in path.size():
		var on : Vector2 = path[i]
		var jit := Vector2(sin(e["t"] * 30.0 + float(i)), cos(e["t"] * 24.0 + float(i))) * 5.0 * fade
		fx_layer.draw_circle(on + jit, fade * (1.5 + float(i % 3)), Color(1.0, 1.0, 0.9, fade * 0.8))
		var rise := 8.0 + 20.0 * fade
		var fl := on + Vector2(sin(e["t"] * 22.0 + float(i) * 1.7) * 5.0, -rise)
		var fsz := fade * (2.0 + float(i % 3) * 1.2)
		if fsz > 0.4:
			fx_layer.draw_circle(fl, fsz, Color(1.0, 0.55, 0.14, fade * 0.5))
			fx_layer.draw_circle(on + Vector2(0, -rise * 0.4), fsz * 0.6, Color(1.0, 0.9, 0.4, fade * 0.6))

func _fx_gravity(e: Dictionary, p: float) -> void:
	var move : Vector2 = e["dir"]
	var board := Rect2(GRID_X - 4, GRID_Y - 4, GRID_COLS * GRID_STEP + 8, GRID_ROWS * GRID_STEP + 8)
	var ek := clampf(p / 0.55, 0.0, 1.0)
	ek = ek * ek
	var fade := 1.0 - clampf((p - 0.5) / 0.5, 0.0, 1.0)
	# speed lines streaking toward the slam edge
	var n := 16
	for i in n:
		var f := (float(i) + 0.5) / float(n)
		var sl := 18.0 + float((i * 5) % 30)
		var cross : float
		if move.x != 0.0:
			cross = board.position.y + f * board.size.y
			var x0 := board.position.x if move.x > 0.0 else board.end.x
			var sx := x0 + move.x * ek * board.size.x * 0.8 + move.x * float((i * 7) % 20)
			fx_layer.draw_line(Vector2(sx, cross), Vector2(sx - move.x * sl, cross),
				Color(1.0, 0.92, 0.55, fade * 0.5), 2.0)
		else:
			cross = board.position.x + f * board.size.x
			var y0 := board.position.y if move.y > 0.0 else board.end.y
			var sy := y0 + move.y * ek * board.size.y * 0.8 + move.y * float((i * 7) % 20)
			fx_layer.draw_line(Vector2(cross, sy), Vector2(cross, sy - move.y * sl),
				Color(1.0, 0.92, 0.55, fade * 0.5), 2.0)
	# edge impact glow when the blocks hit the wall
	if p > 0.45 and p < 0.82:
		var imp := 1.0 - (p - 0.45) / 0.37
		var ec := Color(1.0, 0.95, 0.6, imp * 0.55)
		var w := 6.0 * imp + 1.0
		if move.y > 0.0:
			fx_layer.draw_line(Vector2(board.position.x, board.end.y), board.end, ec, w)
		elif move.y < 0.0:
			fx_layer.draw_line(board.position, Vector2(board.end.x, board.position.y), ec, w)
		elif move.x > 0.0:
			fx_layer.draw_line(Vector2(board.end.x, board.position.y), board.end, ec, w)
		else:
			fx_layer.draw_line(board.position, Vector2(board.position.x, board.end.y), ec, w)
	# Impact dust kicking up along the slammed edge
	if p > 0.45 and p < 0.92:
		var dimp := 1.0 - (p - 0.45) / 0.47
		var grow := (1.0 - dimp) * 16.0 + 3.0
		for i in 8:
			var f := (float(i) + 0.5) / 8.0
			var pp : Vector2
			if move.y != 0.0:
				var ey := board.end.y if move.y > 0.0 else board.position.y
				pp = Vector2(board.position.x + f * board.size.x, ey)
			else:
				var ex := board.end.x if move.x > 0.0 else board.position.x
				pp = Vector2(ex, board.position.y + f * board.size.y)
			fx_layer.draw_circle(pp, grow, Color(0.92, 0.88, 0.74, dimp * 0.20))

# ── Block style renderer — all skins live in BlockSkins.gd (shared) ─────────
func _draw_styled_block(r: Rect2, col: Color, seed_v: int = 0) -> void:
	BlockSkins.paint(self, grid.block_style, r, col, seed_v)

func _is_over_grid(pos: Vector2) -> bool:
	var m := GRID_STEP * 0.5   # small overhang tolerance at the edges
	return pos.x >= GRID_X - m and pos.x <= GRID_X + GRID_COLS * GRID_STEP + m \
		and pos.y >= GRID_Y - m and pos.y <= GRID_Y + GRID_ROWS * GRID_STEP + m

# A release should only PLACE when the shape is over the board AND the finger
# isn't down in the tray zone (releasing there means "put it back / swap another").
# The drag-lift floats the shape above the finger, so both checks matter — without
# the tray check, a swap-release auto-places because the lifted shape still overlaps
# the board.
func _drop_targets_board(finger: Vector2) -> bool:
	if finger.y >= TRAY_Y:
		return false
	return _is_over_grid(finger + Vector2(0, -DRAG_LIFT))

# ── Score popups ──────────────────────────────────────────────────────────────
func _show_score_popup(amount: int, cleared_lines: int, multiplier: int) -> void:
	var lbl := Label.new()
	lbl.text = "+" + str(amount) + ("   x" + str(multiplier) if multiplier > 1 else "")
	lbl.add_theme_font_size_override("font_size", 32 if cleared_lines == 0 else 48)
	var pop_color : Color
	if multiplier >= 3:
		pop_color = Color(0.95, 0.85, 0.15, 1.0)
	elif cleared_lines > 0:
		pop_color = Color(0.20, 0.85, 0.45, 1.0)
	else:
		pop_color = Color(1, 1, 1, 0.9)
	lbl.add_theme_color_override("font_color", pop_color)
	lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.09, 0.85))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size         = Vector2(260, 60)
	lbl.position     = Vector2(77, 120)
	lbl.pivot_offset = Vector2(130, 30)
	lbl.scale        = Vector2(0.4, 0.4)
	ui.add_child(lbl)
	var drift := randf_range(-26.0, 26.0)
	var t := create_tween()
	t.tween_property(lbl, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(lbl, "position", Vector2(77 + drift, 60), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(lbl, "rotation_degrees", drift * 0.18, 0.6).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(lbl, "modulate", Color(pop_color.r, pop_color.g, pop_color.b, 0.0), 0.6)
	t.tween_callback(lbl.queue_free)

# More words per tier for variety — picked randomly each clear.
const PRAISE_WORDS := {
	1: ["NICE!", "SWEET!", "CLEAN!", "TIDY!", "CRISP!", "SNAPPY!"],
	2: ["EXCELLENT!", "GREAT!", "SLICK!", "SHARP!", "DOUBLE!", "COMBO!"],
	3: ["AMAZING!", "TRIPLE!", "SUPERB!", "BLAZING!", "FANTASTIC!"],
	4: ["INCREDIBLE!", "QUAD!", "UNREAL!", "MASSIVE!", "INSANE!"],
	5: ["LEGENDARY!", "GODLIKE!", "UNSTOPPABLE!", "COSMIC!", "MYTHIC!"],
}

# ── Center-banner queue ───────────────────────────────────────────────────────
# Big center messages (clear praise, BOARD CLEAR, biome name) share one screen strip,
# so they're queued and shown one-after-another (a quick cascade) rather than stacked.
# `slot` = the gap before the NEXT banner pops (not the banner's full lifetime).
func _enqueue_banner(fn: Callable, slot: float) -> void:
	banner_queue.append({"fn": fn, "slot": slot})

func _drain_banner_queue(delta: float) -> void:
	if _banner_t > 0.0:
		_banner_t -= delta
	if _banner_t <= 0.0 and not banner_queue.is_empty():
		var b : Dictionary = banner_queue.pop_front()
		var fn : Callable = b["fn"]
		if fn.is_valid():
			fn.call()
		_banner_t = float(b["slot"])

func _show_clear_text(lines: int) -> void:
	if lines == 0:
		return
	_show_praise(clampi(lines, 1, 5))

# Map an ability's cell-clear count to a praise tier ("how much they clear").
func _praise_tier_for_cells(cells: int) -> int:
	if cells <= 5:
		return 1
	elif cells <= 9:
		return 2
	elif cells <= 15:
		return 3
	elif cells <= 23:
		return 4
	return 5

func _show_praise(tier: int) -> void:
	tier = clampi(tier, 1, 5)
	var words : Array = PRAISE_WORDS[tier]
	var text : String = words[randi() % words.size()]
	# Bigger per tier + a tiny bit longer hold than before.
	var fsize  : int   = [46, 60, 74, 84, 94][tier - 1]
	var bounce : float = [1.22, 1.32, 1.44, 1.56, 1.68][tier - 1]
	var hold   : float = [0.50, 0.65, 0.85, 1.05, 1.30][tier - 1]
	var amp    : float = [2.5, 3.5, 4.5, 5.5, 6.5][tier - 1]
	# Queue it so a same-move clear + board-clear + biome banner cascade instead of mashing
	_enqueue_banner(_spawn_praise.bind(text, fsize, bounce, hold, amp), clampf(0.30 + hold, 0.5, 0.9))

# Sum of per-character advance widths at a given size (for centring the letters).
func _measure_word(text: String, fsize: int) -> Dictionary:
	var widths : Array = []
	var total  : float = 0.0
	for ch in text:
		var w : float = _icon_font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		widths.append(w)
		total += w
	return {"widths": widths, "total": total}

# Build a praise popup as ONE Baloo label per letter; _animate_praise then flows a
# rainbow across them + bobs each letter, so it reads as moving rainbow bubble text.
func _spawn_praise(text: String, fsize: int, bounce: float, hold: float, amp: float) -> void:
	var m : Dictionary = _measure_word(text, fsize)
	# Shrink to fit the screen width for long words at big sizes.
	if m["total"] > 392.0:
		fsize = maxi(22, int(float(fsize) * 392.0 / float(m["total"])))
		m = _measure_word(text, fsize)
	var widths : Array = m["widths"]
	var cx : float = 207.0
	# Roomy box so the thick outline never gets clipped flat (that was the "horizontal
	# line" through tall letters); glyphs centre vertically on screen-y 320.
	var lh : float = float(fsize) * 1.85
	var cy : float = 320.0 - lh * 0.5
	var outline : int = clampi(int(round(float(fsize) * 0.17)), 8, 14)  # a touch thicker = bubblier
	var letters : Array = []
	var base_xs : Array = []
	var x_cursor : float = cx - float(m["total"]) * 0.5
	for idx in text.length():
		var ch : String = text[idx]
		var w  : float  = widths[idx]
		var bw : float  = w + float(fsize) * 0.6
		var px : float  = x_cursor + w * 0.5 - bw * 0.5   # centre the glyph on its advance slot
		var lab := Label.new()
		lab.text = ch
		lab.clip_text = false
		lab.add_theme_font_override("font", _icon_font)
		lab.add_theme_font_size_override("font_size", fsize)
		lab.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		lab.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.09, 1))
		lab.add_theme_constant_override("outline_size", outline)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lab.size         = Vector2(bw, lh)
		lab.pivot_offset = Vector2(bw * 0.5, lh * 0.5)
		lab.position     = Vector2(px, cy)
		lab.scale        = Vector2(0.1, 0.1)
		ui.add_child(lab)
		letters.append(lab)
		base_xs.append(px)
		x_cursor += w
	praise_pops.append({
		"letters": letters, "base_xs": base_xs, "cy": cy,
		"t": 0.0, "hold": hold, "bounce": bounce, "amp": amp,
		"hue0": randf(),
	})

# Drives every active praise popup each frame: pop-in bounce → hold → float up + fade,
# with a rainbow that flows across the letters and a per-letter wave bob.
func _animate_praise(delta: float) -> void:
	if praise_pops.is_empty():
		return
	var alive : Array = []
	for e in praise_pops:
		e["t"] += delta
		var t      : float = e["t"]
		var bounce : float = e["bounce"]
		var hold   : float = e["hold"]
		# Scale lifecycle: overshoot in, settle, hold at 1.
		var sc : float
		if t < 0.16:
			sc = _back_out(t / 0.16) * bounce
		elif t < 0.30:
			sc = lerpf(bounce, 1.0, (t - 0.16) / 0.14)
		else:
			sc = 1.0
		var fade_start : float = 0.30 + hold
		var alpha : float = 1.0
		var yoff  : float = 0.0
		if t >= fade_start:
			var fp : float = (t - fade_start) / 0.55
			alpha = clampf(1.0 - fp, 0.0, 1.0)
			yoff  = -fp * 80.0
		var dur : float = fade_start + 0.55
		var letters : Array = e["letters"]
		var base_xs : Array = e["base_xs"]
		var cy : float = e["cy"]
		# Keep the letter colours in the CURRENT biome's family (a hue band around its
		# accent) instead of the full rainbow, so the words blend with each skin — same
		# treatment as the rainbow score. Each letter still ripples for a multi-tone feel.
		var sacc : Color = THEMES[_visual_idx()]["accent"]
		var base_h : float = sacc.h
		var p_sat : float = clampf(sacc.s * 1.15 + 0.12, 0.25, 0.92)
		for i in letters.size():
			var lab : Label = letters[i]
			if not is_instance_valid(lab):
				continue
			var hue : float = fmod(base_h + sin(t * 2.2 + float(i) * 0.55 + float(e["hue0"]) * TAU) * 0.13 + 1.0, 1.0)
			lab.modulate = Color.from_hsv(hue, p_sat, 1.0, alpha)
			var wave : float = sin(t * 7.0 + float(i) * 0.6) * e["amp"] * sc
			lab.position = Vector2(base_xs[i], cy + yoff + wave)
			lab.scale = Vector2(sc, sc)
		if t < dur:
			alive.append(e)
		else:
			for lab in letters:
				if is_instance_valid(lab):
					lab.queue_free()
	praise_pops = alive

func _show_board_clear_popup() -> void:
	_enqueue_banner(_spawn_board_clear_banner, 0.95)

func _spawn_board_clear_banner() -> void:
	# Big rainbow bubble "BOARD CLEAR!" (same moving-rainbow letters as the praise text)
	_spawn_praise("BOARD CLEAR!", 74, 1.58, 1.15, 6.0)
	# Small gold "+points" floater under it
	var lbl := Label.new()
	lbl.text = "+" + str(BOARD_CLEAR_PTS)
	lbl.add_theme_font_size_override("font_size", 40)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0, 1.0))
	lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.09, 0.85))
	lbl.add_theme_constant_override("outline_size", 8)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size     = Vector2(320, 60)
	lbl.position = Vector2(47, 360)
	ui.add_child(lbl)
	var t := create_tween()
	t.tween_property(lbl, "position", Vector2(47, 320), 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(lbl, "modulate", Color(1, 1, 1, 0), 1.1).set_delay(0.6)
	t.tween_callback(lbl.queue_free)

func _update_combo_label() -> void:
	if combo >= 2:
		var mult := minf(1.0 + STREAK_STEP * float(combo - 1), STREAK_CAP)
		combo_label.text = "STREAK  ×" + _fmt_mult(mult)
		combo_label.add_theme_color_override("font_color",
			Color(1.0, 0.72, 0.20).lerp(THEMES[_visual_idx()]["accent"], 0.35))
		combo_label.scale = Vector2(1.3, 1.3)
		var t := create_tween()
		t.tween_property(combo_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)
	elif streak_lost_t > 0.0:
		combo_label.text = "STREAK LOST"
		combo_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	else:
		combo_label.text = ""

func _fmt_mult(m: float) -> String:
	var s := String.num(m, 2)
	if s.contains("."):
		s = s.rstrip("0").rstrip(".")
	return s

# Flame + pill behind the ComboLabel text (label renders above on the
# CanvasLayer). Flickers while hot, greys out during the streak-lost flash.
func _draw_streak_meter() -> void:
	var lost := combo < 2
	var a : float = streak_lost_t if lost else 1.0
	if a <= 0.0:
		return
	var pill := Rect2(112, 558, 190, 34)
	var hot  := clampf(float(combo - 2) / 6.0, 0.0, 1.0)
	var col  : Color = Color(0.55, 0.55, 0.60) if lost else Color(1.0, 0.72, 0.20).lerp(Color(1.0, 0.30, 0.15), hot)
	_rr_fill(pill, 17.0, Color(0, 0, 0, 0.40 * a))
	_rr_outline(pill, 17.0, Color(col.r, col.g, col.b, 0.55 * a), 1.5)
	# Cartoon flame at the left end
	var fx := Vector2(pill.position.x + 22.0, pill.get_center().y + 4.0)
	var flick := sin(Time.get_ticks_msec() * 0.012) * 2.0 if not lost else 0.0
	var tip := fx + Vector2(flick * 0.4, -16.0 - flick)
	draw_polygon(PackedVector2Array([fx + Vector2(-8, 0), tip, fx + Vector2(8, 0)]),
		PackedColorArray([Color(col.r, col.g, col.b, 0.9 * a)]))
	draw_circle(fx, 8.0, Color(col.r, col.g, col.b, 0.9 * a))
	if not lost:
		draw_circle(fx + Vector2(0, 1.5), 4.5, Color(1.0, 0.92, 0.45, 0.95 * a))
		draw_circle(fx + Vector2(0, 2.5), 2.0, Color(1, 1, 1, 0.9 * a))

# ── Helpers ───────────────────────────────────────────────────────────────────
# No piece fits. If a charged power could bail them out, offer a timed rescue
# instead of ending the run; otherwise it's a real game over.
func _try_game_over() -> void:
	if grid.can_any_fit(_shapes_array(), placed):
		return
	if tutorial == null and meter >= METER_BOMB and not rescue_active:
		_begin_rescue()
		return
	_game_over()

func _begin_rescue() -> void:
	rescue_active = true
	rescue_timer  = RESCUE_SECS
	power_pulse   = 1.0
	Sfx.play_tick()
	_buzz(45)
	queue_redraw()

# Called once a fired power finishes. If the board now fits, great. If a piece
# STILL doesn't fit (e.g. an ult that didn't open the right gap), hand over a
# fresh, fitting tray — spending an ability must never end the run.
func _resolve_after_power() -> void:
	if grid.can_any_fit(_shapes_array(), placed):
		if rescue_active:
			rescue_active = false
			Sfx.play_best()
			_buzz(30)
		return
	rescue_active = false
	_spawn_pieces()

func _game_over() -> void:
	rescue_active = false
	run_over = true
	GameState.snapshot(grid.cells, score, pieces, placed,
		sets_given, lines_cleared, theme_idx, combo, placements,
		max_combo, board_clears, grid.seeds, meter)
	GameState.clear_run()
	GameState.finish_run(placements, score, lines_cleared, max_combo, board_clears)
	GameState.record_final_score(score)
	Sfx.play_game_over()
	_buzz(140)
	await get_tree().create_timer(0.9).timeout
	get_tree().change_scene_to_file("res://scenes/GameOver.tscn")

# Auto-save the run after every placement so leaving to the menu (or the app
# being killed) never loses progress. Cleared on game over.
func _save_run() -> void:
	if run_over:
		return
	if tutorial != null:
		return   # scripted tutorial board must never be written as a resumable run
	GameState.snapshot(grid.cells, score, pieces, placed,
		sets_given, lines_cleared, theme_idx, combo, placements,
		max_combo, board_clears, grid.seeds, meter)
	GameState.save_run_to_disk()

func _pop_score(gained: int) -> void:
	# Just a scale bounce — the gold colour flash was removed (it fought the
	# white / rainbow score colour and read as an off-looking yellow blink).
	score_label.scale = Vector2(1.25, 1.25)
	var t := create_tween()
	t.tween_property(score_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)

# Score numeral shrinks as it grows so huge scores (up to 1M+) never overflow.
# Shimmer colour for the high-score glow — kept in the CURRENT biome's colour family
# (a hue band around its accent) so it harmonises with each skin instead of cycling
# the full rainbow (which clashed on coloured biomes). Updates as the skin changes.
func _score_shimmer_color() -> Color:
	var sacc : Color = THEMES[_visual_idx()]["accent"]
	var hue := fmod(sacc.h + sin(Time.get_ticks_msec() * 0.0009) * 0.10 + 1.0, 1.0)
	var sat := clampf(sacc.s * 1.15 + 0.12, 0.18, 0.90)
	return Color.from_hsv(hue, sat, 1.0)

func _set_score_text(n: int) -> void:
	var s := str(n)
	score_label.text = s
	var fs := 80
	if   s.length() >= 7: fs = 50
	elif s.length() == 6: fs = 60
	elif s.length() == 5: fs = 70
	score_label.add_theme_font_size_override("font_size", fs)

func _refresh_best() -> void:
	if GameState.best_score > 0:
		best_label.text = "BEST  " + str(GameState.best_score)

# ── First-run tutorial coach ─────────────────────────────────────────────────
func _start_tutorial() -> void:
	var coach_script := load("res://scripts/Tutorial.gd")
	if coach_script == null:
		return
	tutorial = coach_script.new()
	add_child(tutorial)
	tutorial.begin(self, grid)

# Wipe the board to empty (no animation) — used to stage each tutorial lesson
func tut_clear_board() -> void:
	for r in GRID_ROWS:
		for c in GRID_COLS:
			grid.cells[r][c] = null
			grid.seeds[r][c] = r * 7 + c * 13
	grid.clear_ghost()
	grid.queue_redraw()

func tut_fill_cell(r: int, c: int, col: Color) -> void:
	grid.cells[r][c] = col
	grid.seeds[r][c] = r * 7 + c * 13
	grid.queue_redraw()

# Force the tray to a specific set of pieces (always three; pads colours from COLORS)
func tut_set_pieces(shapes: Array) -> void:
	pieces = []
	for i in shapes.size():
		var sh : Array  = shapes[i]
		var cl : Color  = COLORS[i % COLORS.size()]
		pieces.append({"shape": sh, "color": cl, "pattern": (i + 1) * 4099})
	placed        = [false, false, false]
	dragging_slot = -1
	tray_pop_t    = 1.0
	queue_redraw()

func tut_set_meter(v: float) -> void:
	meter = clampf(v, 0.0, METER_FULL)
	queue_redraw()

# Lock guided placement to one piece + one cell (magnetised); -1 slot clears it
func tut_lock(slot: int, cell: Vector2i) -> void:
	tut_lock_slot = slot
	tut_lock_cell = cell

func tut_unlock() -> void:
	tut_lock_slot = -1

# Tutorial complete: drop the coach and let the SAME run continue seamlessly —
# the board, score and pieces they built during the lesson are now their run.
func tut_finish() -> void:
	if tutorial != null:
		tutorial.queue_free()
		tutorial = null
	tut_unlock()
	GameState.tutorial_active = false
	GameState.tutorial_done   = true
	GameState._save()
	_save_run()

# ── Pause / settings overlay ─────────────────────────────────────────────────
func _make_chunky_button(label_text: String, fill: Color, font_size: int = 20) -> Button:
	var b := Button.new()
	b.text = label_text
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(18)
	sb.border_width_bottom = 6
	sb.border_color = fill.darkened(0.40)
	var sb_hover := sb.duplicate()
	sb_hover.bg_color = fill.lightened(0.10)
	var sb_press := sb.duplicate()
	sb_press.bg_color = fill.darkened(0.10)
	sb_press.border_width_bottom = 2
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb_hover)
	b.add_theme_stylebox_override("pressed", sb_press)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_size_override("font_size", font_size)
	var fc := Color(0.08, 0.06, 0.12)
	b.add_theme_color_override("font_color", fc)
	b.add_theme_color_override("font_hover_color", fc)
	b.add_theme_color_override("font_pressed_color", fc)
	_add_press_effect(b)
	return b

# Press-and-hold sinks the button face by the same 5px the bottom edge
# collapses, so it physically pushes in; release springs it back out.
func _add_press_effect(b: Button) -> void:
	b.button_down.connect(func():
		Sfx.play_tick()
		if b.has_meta("press_tw"):
			var old: Tween = b.get_meta("press_tw")
			if old and old.is_valid(): old.kill()
		b.set_meta("press_y", b.position.y)
		var t := b.create_tween()
		b.set_meta("press_tw", t)
		t.tween_property(b, "position:y", b.position.y + 5.0, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT))
	b.button_up.connect(func():
		if not b.has_meta("press_y"):
			return
		if b.has_meta("press_tw"):
			var old: Tween = b.get_meta("press_tw")
			if old and old.is_valid(): old.kill()
		var t := b.create_tween()
		b.set_meta("press_tw", t)
		t.tween_property(b, "position:y", float(b.get_meta("press_y")), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))

func _build_pause_menu() -> void:
	pause_menu = Control.new()
	pause_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_menu.visible = false
	ui.add_child(pause_menu)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_menu.add_child(dim)

	var panel := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.12, 0.10, 0.18)
	psb.set_corner_radius_all(24)
	psb.border_width_bottom = 8
	psb.border_color = Color(0.06, 0.05, 0.10)
	psb.content_margin_left = 28; psb.content_margin_right = 28
	psb.content_margin_top = 24;  psb.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", psb)
	panel.position = Vector2(57, 250)
	panel.custom_minimum_size = Vector2(300, 0)
	pause_menu.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var resume := _make_chunky_button("RESUME", Color(0.20, 0.85, 0.45))
	resume.custom_minimum_size = Vector2(0, 56)
	resume.pressed.connect(_toggle_pause_menu)
	vbox.add_child(resume)

	var snd := _make_chunky_button(_sound_text(), Color(0.20, 0.75, 0.95))
	snd.custom_minimum_size = Vector2(0, 56)
	snd.pressed.connect(func():
		GameState.set_sound(not GameState.sound_on)
		snd.text = _sound_text()
		Sfx.play_click())
	vbox.add_child(snd)

	var mus := _make_chunky_button(_music_text(), Color(0.65, 0.30, 0.95))
	mus.custom_minimum_size = Vector2(0, 56)
	mus.pressed.connect(func():
		GameState.set_music(not GameState.music_on)
		Sfx.update_music()
		mus.text = _music_text()
		Sfx.play_click())
	vbox.add_child(mus)

	var hap := _make_chunky_button(_haptics_text(), Color(0.95, 0.75, 0.15))
	hap.custom_minimum_size = Vector2(0, 56)
	hap.pressed.connect(func():
		GameState.set_haptics(not GameState.haptics_on)
		hap.text = _haptics_text()
		_buzz(30)
		Sfx.play_click())
	vbox.add_child(hap)

	var menu := _make_chunky_button("MAIN MENU", Color(0.90, 0.30, 0.40))
	menu.custom_minimum_size = Vector2(0, 56)
	menu.pressed.connect(func():
		Sfx.play_click()
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	vbox.add_child(menu)

func _sound_text() -> String:
	return "SOUND: ON" if GameState.sound_on else "SOUND: OFF"

func _music_text() -> String:
	return "MUSIC: ON" if GameState.music_on else "MUSIC: OFF"

func _haptics_text() -> String:
	return "HAPTICS: ON" if GameState.haptics_on else "HAPTICS: OFF"

func _toggle_pause_menu() -> void:
	menu_open = not menu_open
	pause_menu.visible = menu_open
	Sfx.play_click()
	if menu_open and dragging_slot >= 0:
		dragging_slot = -1
		grid.clear_ghost()
	if menu_open:
		# Pop-in bounce
		pause_menu.scale = Vector2(0.85, 0.85)
		pause_menu.pivot_offset = Vector2(207, 448)
		var t := create_tween()
		t.tween_property(pause_menu, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
