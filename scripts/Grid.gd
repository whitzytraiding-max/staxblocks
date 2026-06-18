class_name Grid
extends Node2D

const COLS := 8
const ROWS := 8
const CELL := 44.0
const GAP  := 2.0
const STEP := CELL + GAP
const RAD  := 7.0    # corner radius for the bubbly look
const BOARD_SPAN := COLS * STEP - GAP    # 366 px: cell-area edge to edge
const FRAME_MARGIN := 40.0               # glow room around the board for the frame

var cells       : Array = []
var seeds       : Array = []   # per-cell skin pattern seed — each piece is a
							   # random "crop" of the skin canvas (CSGO style)
var ghost_cells : Array[Vector2i] = []
var ghost_color := Color.TRANSPARENT
var block_style : int = 0   # set by Game.gd on theme change

# Clear-preview: cells of any row/col that would complete at the ghost position
var preview_cells : Array[Vector2i] = []
var preview_color := Color.TRANSPARENT

var last_lines_cleared : int = 0

# Animated skins (water/lava/galaxy…) repaint all 64 cells every frame, which is
# the heaviest per-frame cost on mobile. Throttle that decorative shimmer to
# ~30fps; gameplay redraws (place/clear/slam/preview) still fire immediately.
var _anim_accum : float = 0.0

# Clear pop animation: per-cell colour, cascade delay and burst particles
const POP_DUR   := 0.38
var clear_anim  : Array = []
var clear_t     : float = 0.0
var clear_total : float = 0.0
var clearing    : bool  = false

# Placement squash & stretch
const PLACE_DUR := 0.30
var place_anim  : Array = []

var last_place_center := Vector2.ZERO

# Board-frame reaction: spikes on a clear, decays — drives the border flare
var frame_pulse : float = 0.0
var frame_rect : ColorRect          # GPU-shader layer for the animated border
var frame_mat  : ShaderMaterial
var _frame_fs  : float

# Reused draw buffers — avoid allocating a fresh PackedArray on every rounded-rect
# fill/outline (2+ per cell × 64 cells per redraw = the GC churn behind the hitches).
# draw_polygon/draw_polyline copy on submit, so reusing one buffer is safe.
var _rrbuf    : PackedVector2Array = PackedVector2Array()
var _rrclosed : PackedVector2Array = PackedVector2Array()
var _rrcol    : PackedColorArray   = PackedColorArray([Color.WHITE])
var _rrgrad   : PackedColorArray   = PackedColorArray()

func _bump_frame(strong: bool) -> void:
	frame_pulse = maxf(frame_pulse, 1.5 if strong else 0.85)

# Gravity-slam slide (the ultimate power) — blocks fly to one edge, then settle
const SLAM_DUR := 0.42
var slamming  : bool  = false
var slam_t    : float = 0.0
var slam_anim : Array = []   # {from: px, to: px, color, seed}

func _ready() -> void:
	cells.resize(ROWS)
	seeds.resize(ROWS)
	for r in ROWS:
		cells[r] = []
		cells[r].resize(COLS)
		cells[r].fill(null)
		seeds[r] = []
		seeds[r].resize(COLS)
		for c in COLS:
			seeds[r][c] = r * 7 + c * 13

	# Animated multicolour border: a single GPU-shader ColorRect. It animates on
	# the GPU via TIME, so there is NO per-frame redraw and it stays perfectly
	# smooth (true SDF rounded corners). We only push the clear-flare + biome hue.
	# The rect is added as a SIBLING of Grid (not a child) so it always renders
	# behind Grid's own draw, guaranteeing blocks appear on top of the border.
	var fs := BOARD_SPAN + 2.0 * FRAME_MARGIN
	_frame_fs = fs
	frame_mat = ShaderMaterial.new()
	frame_mat.shader = load("res://assets/shaders/board_frame.gdshader")
	frame_mat.set_shader_parameter("u_size", Vector2(fs, fs))
	frame_mat.set_shader_parameter("u_half", BOARD_SPAN * 0.5 + 6.0)
	frame_mat.set_shader_parameter("u_radius", 16.0)
	frame_mat.set_shader_parameter("u_thickness", 3.0)
	frame_rect = ColorRect.new()
	frame_rect.material = frame_mat
	frame_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame_rect.size = Vector2(fs, fs)
	frame_rect.z_index = 0
	call_deferred("_add_frame_behind_grid")

func _add_frame_behind_grid() -> void:
	var parent := get_parent()
	# Position in parent (Game) space: Grid position + frame offset within Grid
	frame_rect.position = position + Vector2(BOARD_SPAN * 0.5 - _frame_fs * 0.5,
											 BOARD_SPAN * 0.5 - _frame_fs * 0.5)
	parent.add_child(frame_rect)
	parent.move_child(frame_rect, 0)  # first child = renders before Grid

func _process(delta: float) -> void:
	var needs_redraw := false

	var done: Array = []
	for pa in place_anim:
		pa["t"] += delta / PLACE_DUR
		if pa["t"] >= 1.0:
			done.append(pa)
		needs_redraw = true
	for pa in done:
		place_anim.erase(pa)

	if clearing:
		clear_t += delta
		if clear_t >= clear_total:
			clearing   = false
			clear_anim = []
			clear_t    = 0.0
		needs_redraw = true

	if slamming:
		slam_t += delta
		if slam_t >= SLAM_DUR:
			slamming  = false
			slam_anim = []
			slam_t    = 0.0
		needs_redraw = true

	# Preview pulse needs continuous redraw while active
	if not preview_cells.is_empty():
		needs_redraw = true

	# Animated skins live-update on a ~30fps budget (perf: 64 complex cell paints
	# per frame is the main mobile cost; halving it is a big saving, barely visible)
	if BlockSkins.ANIMATED.has(block_style):
		_anim_accum += delta
		if _anim_accum >= 1.0 / 30.0:
			_anim_accum = 0.0
			needs_redraw = true

	# Board frame: decay the clear-flare and push it + the biome hue to the shader.
	# The border animates on the GPU, so nothing needs to redraw here.
	if frame_pulse > 0.0:
		frame_pulse = maxf(0.0, frame_pulse - delta * 2.2)
	frame_mat.set_shader_parameter("u_pulse", frame_pulse)
	var acc : Color = GameState.THEMES[block_style % GameState.THEMES.size()].get("accent", Color(0.6, 0.8, 1.0))
	frame_mat.set_shader_parameter("u_col", Vector3(acc.r, acc.g, acc.b))

	if needs_redraw:
		queue_redraw()

func _draw() -> void:
	if slamming:
		_draw_slam()
		return
	# Precompute once per redraw instead of per-cell (was 64 sin() + 64 linear
	# Array.has() scans + a place_anim loop per cell — pure overhead on a full board).
	var pulse := (sin(Time.get_ticks_msec() * 0.012) + 1.0) * 0.5
	var ghost_set : Dictionary = {}
	for g in ghost_cells:
		ghost_set[g] = true
	var preview_set : Dictionary = {}
	for p in preview_cells:
		preview_set[p] = true
	var place_map : Dictionary = {}
	for pa in place_anim:
		place_map[Vector2i(pa["c"], pa["r"])] = pa["t"]

	for r in ROWS:
		for c in COLS:
			_draw_cell(r, c, pulse, ghost_set, preview_set, place_map)
	# Drips (honey/slime) hang below blocks — painted after ALL cells so the
	# row beneath doesn't cover them
	if BlockSkins.OVERLAY_STYLES.has(block_style):
		for r in ROWS:
			for c in COLS:
				if cells[r][c] != null:
					BlockSkins.paint_overlay(self, block_style,
						Rect2(c * STEP, r * STEP, CELL, CELL), cells[r][c], seeds[r][c])
	if clearing:
		_draw_clear_pop()

func _draw_cell(r: int, c: int, pulse: float, ghost_set: Dictionary,
		preview_set: Dictionary, place_map: Dictionary) -> void:
	var rect := Rect2(c * STEP, r * STEP, CELL, CELL)
	var col  : Color = cells[r][c] if cells[r][c] != null else Color.TRANSPARENT
	var gv   := Vector2i(c, r)

	var in_preview := preview_set.has(gv)

	if col == Color.TRANSPARENT:
		if ghost_set.has(gv):
			var ga := 0.42 if in_preview else 0.30
			_rounded_rect(rect, RAD, Color(ghost_color.r, ghost_color.g, ghost_color.b, ga))
			_rounded_outline(rect, RAD, Color(ghost_color.r, ghost_color.g, ghost_color.b, 0.75), 1.5)
		else:
			_rounded_rect(rect, RAD, Color(0.13, 0.11, 0.19))
			_rounded_outline(rect, RAD, Color(0.24, 0.20, 0.32), 1.0)
		return

	# Filled cell that's part of a line about to clear: tint toward the
	# dragged piece's colour + pulsing bright border
	if in_preview:
		col = col.lerp(preview_color.lightened(0.25), 0.55 + pulse * 0.20)

	var sc := Vector2.ONE
	if place_map.has(gv):
		var pt : float = place_map[gv]
		sc = _squash_scale(clampf(pt, 0.0, 1.0))
		# Brief white "landing" flash as the block settles (on top of the squash)
		if pt >= 0.0 and pt < 0.30:
			col = col.lerp(Color(1, 1, 1), (1.0 - pt / 0.30) * 0.45)

	var drv := rect
	if sc != Vector2.ONE:
		var center := rect.get_center()
		var size   := Vector2(CELL * sc.x, CELL * sc.y)
		drv = Rect2(center - size * 0.5, size)

	# Steady glow with only a gentle breathe — a full-range pulse reads as flashing
	_draw_block(drv, col, seeds[r][c], (0.82 + pulse * 0.18) if in_preview else 0.0, rect)

	if in_preview:
		_rounded_outline(drv.grow(1.0), RAD + 1.0, Color(1, 1, 1, 0.45 + pulse * 0.45), 2.5)

	if sc.x > 1.05:
		var glow_a := (sc.x - 1.0) / 0.30 * 0.5
		_rounded_outline(drv.grow(4), RAD + 3.0, Color(col.r, col.g, col.b, glow_a), 3.0)

# All skin rendering lives in BlockSkins.gd (shared with tray + menus).
# pr = the cell's resting rect, so canvas-continuous patterns hold steady
# while the squash/stretch animation plays.
func _draw_block(r: Rect2, col: Color, seed_v: int = 0, glow: float = 0.0, pr: Rect2 = Rect2()) -> void:
	BlockSkins.paint(self, block_style, r, col, seed_v, glow, pr, false)   # overlay drawn in a later pass

# ── Squash & stretch curve ────────────────────────────────────────────────────
# Land fat and short, overshoot tall and thin, elastic settle
func _squash_scale(t: float) -> Vector2:
	if t < 0.30:
		var k := t / 0.30
		k = 1.0 - (1.0 - k) * (1.0 - k)   # ease-out
		return Vector2(lerpf(1.32, 0.88, k), lerpf(0.68, 1.18, k))
	elif t < 0.65:
		var k := (t - 0.30) / 0.35
		return Vector2(lerpf(0.88, 1.06, k), lerpf(1.18, 0.95, k))
	else:
		var k := (t - 0.65) / 0.35
		return Vector2(lerpf(1.06, 1.0, k), lerpf(0.95, 1.0, k))

# ── Rounded drawing helpers ───────────────────────────────────────────────────
# Reuse BlockSkins' precomputed 16 corner unit-directions (no per-call cos/sin).
# Hot: every empty board cell draws a rounded fill + outline each redraw.
func _rounded_points(r: Rect2, rad: float) -> PackedVector2Array:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	var c0 := Vector2(r.position.x + rad, r.position.y + rad)
	var c1 := Vector2(r.end.x - rad,      r.position.y + rad)
	var c2 := Vector2(r.end.x - rad,      r.end.y - rad)
	var c3 := Vector2(r.position.x + rad, r.end.y - rad)
	if _rrbuf.size() != 16:
		_rrbuf.resize(16)
	for i in 4:
		_rrbuf[i]      = c0 + BlockSkins._RR_UNIT[i] * rad
		_rrbuf[4 + i]  = c1 + BlockSkins._RR_UNIT[4 + i] * rad
		_rrbuf[8 + i]  = c2 + BlockSkins._RR_UNIT[8 + i] * rad
		_rrbuf[12 + i] = c3 + BlockSkins._RR_UNIT[12 + i] * rad
	return _rrbuf

func _rounded_rect(r: Rect2, rad: float, col: Color) -> void:
	_rrcol[0] = col
	draw_polygon(_rounded_points(r, rad), _rrcol)

func _rounded_outline(r: Rect2, rad: float, col: Color, width: float) -> void:
	var pts := _rounded_points(r, rad)
	if _rrclosed.size() != 17:
		_rrclosed.resize(17)
	for i in 16:
		_rrclosed[i] = pts[i]
	_rrclosed[16] = pts[0]
	draw_polyline(_rrclosed, col, width)

func _rounded_gradient(r: Rect2, rad: float, top_col: Color, bot_col: Color) -> void:
	var pts := _rounded_points(r, rad)
	if _rrgrad.size() != pts.size():
		_rrgrad.resize(pts.size())
	for i in pts.size():
		_rrgrad[i] = top_col.lerp(bot_col, clampf((pts[i].y - r.position.y) / r.size.y, 0.0, 1.0))
	draw_polygon(pts, _rrgrad)

# ── Clear pop animation ───────────────────────────────────────────────────────
# Each cleared cell pops: scales up bright, then shrinks to nothing while
# spitting tiny coloured particles. Cascades outward from the placed piece.
func _draw_clear_pop() -> void:
	for ca in clear_anim:
		var lt : float = clampf((clear_t - ca["delay"]) / POP_DUR, 0.0, 1.0)
		if lt <= 0.0:
			# Not started yet — cell already nulled, draw it intact while waiting
			var rect0 := Rect2(ca["pos"].x * STEP, ca["pos"].y * STEP, CELL, CELL)
			_draw_block(rect0, ca["color"], ca["seed"])
			continue
		if lt >= 1.0:
			continue
		var center := Vector2(ca["pos"].x * STEP + CELL * 0.5, ca["pos"].y * STEP + CELL * 0.5)
		var col    : Color = ca["color"]
		var scale_f : float
		var alpha   : float
		if lt < 0.35:
			var k := lt / 0.35
			scale_f = lerpf(1.0, 1.35, k)
			alpha   = 1.0
			col     = col.lerp(Color.WHITE, k * 0.7)
		else:
			var k := (lt - 0.35) / 0.65
			scale_f = lerpf(1.35, 0.0, k * k)
			alpha   = 1.0 - k
			col     = col.lerp(Color.WHITE, 0.7 * (1.0 - k))
		if scale_f > 0.01:
			var size := Vector2(CELL, CELL) * scale_f
			_rounded_rect(Rect2(center - size * 0.5, size), RAD * scale_f,
				Color(col.r, col.g, col.b, alpha))
		# Particles fly outward and shrink
		if lt > 0.15:
			var pk := (lt - 0.15) / 0.85
			for part in ca["parts"]:
				var ppos : Vector2 = center + part["dir"] * part["spd"] * pk
				var psz  : float   = part["size"] * (1.0 - pk)
				if psz > 0.5:
					draw_rect(Rect2(ppos - Vector2(psz, psz) * 0.5, Vector2(psz, psz)),
						Color(ca["color"].r, ca["color"].g, ca["color"].b, 1.0 - pk), true)

# ── Grid logic ────────────────────────────────────────────────────────────────
func can_place(shape: Array, row: int, col: int) -> bool:
	for cell in shape:
		var r : int = row + cell[1]
		var c : int = col + cell[0]
		if r < 0 or r >= ROWS or c < 0 or c >= COLS:
			return false
		if cells[r][c] != null:
			return false
	return true

func place(shape: Array, row: int, col: int, color: Color, pattern: int = -1) -> void:
	var idx := 0
	var cx  := 0.0
	var cy  := 0.0
	for cell in shape:
		var r : int = row + cell[1]
		var c : int = col + cell[0]
		cells[r][c] = color
		# Pattern crop: cells of one piece share a random canvas region
		seeds[r][c] = (pattern + cell[0] * 7 + cell[1] * 13) if pattern >= 0 else (r * 7 + c * 13)
		place_anim.append({"r": r, "c": c, "t": -float(idx) * 0.10})
		cx += c; cy += r
		idx += 1
	last_place_center = Vector2(cx / shape.size(), cy / shape.size())
	ghost_cells   = []
	preview_cells = []
	queue_redraw()

func check_and_clear() -> int:
	var full_rows : Array[int] = []
	var full_cols : Array[int] = []

	for r in ROWS:
		var full := true
		for c in COLS:
			if cells[r][c] == null:
				full = false; break
		if full: full_rows.append(r)

	for c in COLS:
		var full := true
		for r in ROWS:
			if cells[r][c] == null:
				full = false; break
		if full: full_cols.append(c)

	last_lines_cleared = full_rows.size() + full_cols.size()

	if full_rows.is_empty() and full_cols.is_empty():
		return 0

	# Collect cleared cells with their colours before nulling
	var clear_cells : Array[Vector2i] = []
	for r in full_rows:
		for c in COLS:
			clear_cells.append(Vector2i(c, r))
	for c in full_cols:
		for r in ROWS:
			var cv := Vector2i(c, r)
			if not clear_cells.has(cv):
				clear_cells.append(cv)

	clear_anim  = []
	clear_total = 0.0
	for cv in clear_cells:
		var ccol : Color = cells[cv.y][cv.x]
		var cseed : int = seeds[cv.y][cv.x]
		var delay : float = Vector2(cv.x, cv.y).distance_to(last_place_center) * 0.045
		clear_total = maxf(clear_total, delay + POP_DUR)
		var parts : Array = []
		for i in 5:
			var ang := (float(i) / 5.0 + float((cv.x * 3 + cv.y * 5 + i) % 7) * 0.02) * TAU
			parts.append({
				"dir":  Vector2(cos(ang), sin(ang)),
				"spd":  26.0 + float((cv.x + cv.y * 2 + i * 3) % 5) * 7.0,
				"size": 4.0 + float(i % 3) * 2.0,
			})
		clear_anim.append({"pos": cv, "color": ccol, "seed": cseed, "delay": delay, "parts": parts})

	for r in full_rows:
		for c in COLS: cells[r][c] = null
	for c in full_cols:
		for r in ROWS: cells[r][c] = null

	clear_t  = 0.0
	clearing = true
	_bump_frame(is_board_empty())
	queue_redraw()

	# Returns CELLS cleared (crossing lines share cells) — Game.gd owns
	# all point math
	return clear_cells.size()

func is_board_empty() -> bool:
	for r in ROWS:
		for c in COLS:
			if cells[r][c] != null:
				return false
	return true

# How many rows+cols would complete if shape lands at (row,col).
# Used by the smart spawner to find combo-enabling shapes.
func count_completed_lines(shape: Array, row: int, col: int) -> int:
	var shape_set := {}
	for cell in shape:
		shape_set[Vector2i(col + cell[0], row + cell[1])] = true
	var n := 0
	for r in ROWS:
		var full := true
		for c in COLS:
			if cells[r][c] == null and not shape_set.has(Vector2i(c, r)):
				full = false; break
		if full: n += 1
	for c in COLS:
		var full := true
		for r in ROWS:
			if cells[r][c] == null and not shape_set.has(Vector2i(c, r)):
				full = false; break
		if full: n += 1
	return n

# All cells of every row/col that would become full if shape lands at (row,col)
func get_completed_lines(shape: Array, row: int, col: int) -> Array[Vector2i]:
	var shape_set := {}
	for cell in shape:
		shape_set[Vector2i(col + cell[0], row + cell[1])] = true

	var out : Array[Vector2i] = []
	for r in ROWS:
		var full := true
		for c in COLS:
			if cells[r][c] == null and not shape_set.has(Vector2i(c, r)):
				full = false; break
		if full:
			for c in COLS:
				out.append(Vector2i(c, r))
	for c in COLS:
		var full := true
		for r in ROWS:
			if cells[r][c] == null and not shape_set.has(Vector2i(c, r)):
				full = false; break
		if full:
			for r in ROWS:
				var cv := Vector2i(c, r)
				if not out.has(cv):
					out.append(cv)
	return out

func set_ghost(shape: Array, row: int, col: int, color: Color) -> void:
	ghost_cells = []
	ghost_color = color
	for cell in shape:
		var r : int = row + cell[1]
		var c : int = col + cell[0]
		if r >= 0 and r < ROWS and c >= 0 and c < COLS:
			ghost_cells.append(Vector2i(c, r))
	preview_cells = get_completed_lines(shape, row, col)
	preview_color = color
	queue_redraw()

func clear_ghost() -> void:
	if not ghost_cells.is_empty() or not preview_cells.is_empty():
		ghost_cells   = []
		preview_cells = []
		queue_redraw()

func can_any_fit(pieces: Array, placed: Array) -> bool:
	for i in pieces.size():
		if placed[i]: continue
		for r in ROWS:
			for c in COLS:
				if can_place(pieces[i], r, c):
					return true
	return false

# ── Power abilities ───────────────────────────────────────────────────────────
# Shared shatter starter: pops the given filled cells (reusing the clear-pop
# animation + particles), nulls them, and returns how many actually cleared.
func _start_pop(cell_list: Array, origin: Vector2) -> int:
	clear_anim  = []
	clear_total = 0.0
	var n := 0
	for cv : Vector2i in cell_list:
		if cells[cv.y][cv.x] == null:
			continue
		var ccol  : Color = cells[cv.y][cv.x]
		var cseed : int   = seeds[cv.y][cv.x]
		var delay : float = Vector2(cv.x, cv.y).distance_to(origin) * 0.04
		clear_total = maxf(clear_total, delay + POP_DUR)
		var parts : Array = []
		for i in 5:
			var ang := (float(i) / 5.0 + float((cv.x * 3 + cv.y * 5 + i) % 7) * 0.02) * TAU
			parts.append({
				"dir":  Vector2(cos(ang), sin(ang)),
				"spd":  26.0 + float((cv.x + cv.y * 2 + i * 3) % 5) * 7.0,
				"size": 4.0 + float(i % 3) * 2.0,
			})
		clear_anim.append({"pos": cv, "color": ccol, "seed": cseed, "delay": delay, "parts": parts})
		cells[cv.y][cv.x] = null
		n += 1
	clear_t  = 0.0
	clearing = true
	if n > 0:
		_bump_frame(is_board_empty())
	queue_redraw()
	return n

# BOMB: shatter a (2*radius+1)² block around (cr,cc). radius 1 = 3×3.
func bomb_clear(cr: int, cc: int, radius: int) -> int:
	var cell_list : Array = []
	for dr in range(-radius, radius + 1):
		for dc in range(-radius, radius + 1):
			var r := cr + dr
			var c := cc + dc
			if r >= 0 and r < ROWS and c >= 0 and c < COLS:
				cell_list.append(Vector2i(c, r))
	return _start_pop(cell_list, Vector2(cc, cr))

# Clear an arbitrary set of cells (grid coords) with the shatter animation.
func pop_cells(cell_list: Array, origin: Vector2) -> int:
	return _start_pop(cell_list, origin)

# GRAVITY SLAM: compact every block toward `dir` (one of the 4 axes). Commits
# the new packed board immediately and animates the slide; Game calls
# check_and_clear() once the slide settles to pop any completed lines.
func start_slam(dir: Vector2i) -> void:
	var new_cells : Array = []
	var new_seeds : Array = []
	for r in ROWS:
		var row_c : Array = []; row_c.resize(COLS); row_c.fill(null)
		var row_s : Array = []; row_s.resize(COLS); row_s.fill(0)
		new_cells.append(row_c)
		new_seeds.append(row_s)
	slam_anim = []
	if dir.y != 0:
		for c in COLS:
			var filled : Array = []
			for r in ROWS:
				if cells[r][c] != null:
					filled.append({"i": r, "color": cells[r][c], "seed": seeds[r][c]})
			var cnt := filled.size()
			for i in cnt:
				var nr : int = (ROWS - cnt + i) if dir.y > 0 else i
				var item : Dictionary = filled[i]
				new_cells[nr][c] = item["color"]
				new_seeds[nr][c] = item["seed"]
				slam_anim.append({
					"from": Vector2(c * STEP, int(item["i"]) * STEP),
					"to":   Vector2(c * STEP, nr * STEP),
					"color": item["color"], "seed": item["seed"]})
	else:
		for r in ROWS:
			var filled : Array = []
			for c in COLS:
				if cells[r][c] != null:
					filled.append({"i": c, "color": cells[r][c], "seed": seeds[r][c]})
			var cnt := filled.size()
			for i in cnt:
				var nc : int = (COLS - cnt + i) if dir.x > 0 else i
				var item : Dictionary = filled[i]
				new_cells[r][nc] = item["color"]
				new_seeds[r][nc] = item["seed"]
				slam_anim.append({
					"from": Vector2(int(item["i"]) * STEP, r * STEP),
					"to":   Vector2(nc * STEP, r * STEP),
					"color": item["color"], "seed": item["seed"]})
	cells = new_cells
	seeds = new_seeds
	last_place_center = Vector2(3.5, 3.5)
	slam_t   = 0.0
	slamming = true
	queue_redraw()

# After a slam settles: shatter the impact edge (the wall the blocks hit) PLUS
# any fully completed row/col. The impact line clears even if it has gaps — the
# slam "smashed" it. Sets last_lines_cleared for scoring; returns cells removed.
func slam_clear(dir: Vector2i) -> int:
	var clear_rows : Dictionary = {}
	var clear_cols : Dictionary = {}
	for r in ROWS:
		var full := true
		for c in COLS:
			if cells[r][c] == null:
				full = false; break
		if full: clear_rows[r] = true
	for c in COLS:
		var full := true
		for r in ROWS:
			if cells[r][c] == null:
				full = false; break
		if full: clear_cols[c] = true
	# The edge the blocks slammed into always shatters
	if dir.y > 0:    clear_rows[ROWS - 1] = true
	elif dir.y < 0:  clear_rows[0] = true
	elif dir.x > 0:  clear_cols[COLS - 1] = true
	elif dir.x < 0:  clear_cols[0] = true
	last_lines_cleared = clear_rows.size() + clear_cols.size()
	var cell_list : Array = []
	for r in clear_rows:
		for c in COLS:
			cell_list.append(Vector2i(c, r))
	for c in clear_cols:
		for r in ROWS:
			if not clear_rows.has(r):
				cell_list.append(Vector2i(c, r))
	return _start_pop(cell_list, last_place_center)

# Slide render: empty board with blocks accelerating toward their packed spots.
func _draw_slam() -> void:
	for r in ROWS:
		for c in COLS:
			var rect := Rect2(c * STEP, r * STEP, CELL, CELL)
			_rounded_rect(rect, RAD, Color(0.13, 0.11, 0.19))
			_rounded_outline(rect, RAD, Color(0.24, 0.20, 0.32), 1.0)
	var k : float = clampf(slam_t / SLAM_DUR, 0.0, 1.0)
	k = k * k   # accelerate into the wall, like gravity
	for sa in slam_anim:
		var from_p : Vector2 = sa["from"]
		var to_p   : Vector2 = sa["to"]
		var p := from_p.lerp(to_p, k)
		# motion streak for fast movers
		var travel := from_p.distance_to(to_p)
		if travel > STEP * 0.5 and k > 0.05 and k < 0.98:
			var trail := p.lerp(from_p, 0.35)
			_rounded_rect(Rect2(trail, Vector2(CELL, CELL)),
				RAD, Color(sa["color"].r, sa["color"].g, sa["color"].b, 0.18))
		var rect := Rect2(p, Vector2(CELL, CELL))
		_draw_block(rect, sa["color"], sa["seed"], 0.0, rect)
