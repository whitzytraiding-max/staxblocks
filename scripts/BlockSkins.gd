class_name BlockSkins
extends RefCounted

# Single source of truth for all block skin rendering. Everything is
# proportional to the rect size, so the same painter draws 44px board cells,
# 28px tray pieces and 12px menu fallers identically.
# Used by Grid.gd (board), Game.gd (tray + dragged piece) and the menus
# (falling background pieces).
#
# Styles: 0 PASTEL  1 NEON  2 CIRCUIT  3 BRICK  4 CRYSTAL  5 CANDY
#         6 FROST   7 GRASS 8 WATER    9 LAVA  10 WOOD    11 GALAXY
# Animated (need per-frame redraw): 8, 9, 11

const ANIMATED : Array = [2, 6, 7, 8, 9, 11, 12, 14, 15, 16, 17, 18, 19, 20, 21, 23, 24, 25, 26, 28, 29, 30]

# Rarity per skin (0 COMMON · 1 RARE · 2 EPIC · 3 LEGENDARY), mirrors the Biomes
# gallery tiers.
const RARITY : Array = [
	0, 0, 0, 0, 0,  1, 1, 1, 1, 2,  1, 3, 2, 1, 2,
	3, 3, 2, 1, 2,  3, 3, 2, 3, 3,  3, 2, 2, 2, 2,  3,
]

# 4x4 ordered-dither (Bayer) matrix — the classic limited-palette gradient trick
const BAYER4 : Array = [
	[0, 8, 2, 10],
	[12, 4, 14, 6],
	[3, 11, 1, 9],
	[15, 7, 13, 5],
]

# Styles whose effects hang BELOW the block (drips) — on the grid these must
# be painted in a second pass after all cells, or the row below covers them
const OVERLAY_STYLES : Array = [12, 18]

# Reused single-colour buffer for draw_polygon — avoids allocating a fresh
# PackedColorArray on every one of the ~1000s of poly fills per frame (the GC
# churn that caused occasional hitches). draw_polygon copies it on submit, so
# reusing one shared buffer is safe.
static var _cbuf : PackedColorArray = PackedColorArray([Color(1, 1, 1, 1)])
# Reused per-vertex colour buffers for rr_grad / draw_poly_safe — same churn
# avoidance. Resized only when the vertex count changes, then filled in place.
static var _gradbuf : PackedColorArray = PackedColorArray()
static var _tribuf  : PackedColorArray = PackedColorArray()

# The 16 rounded-corner unit directions are CONSTANT — precomputed once so
# rr_points() is pure add/multiply instead of 16 cos + 16 sin per call (it runs
# ~4× per cell × 64 cells every redraw). Order: TL, TR, BR, BL corners, 4 pts
# each, matching the original lerp(angle) sweep exactly.
# static var (not const): a PackedVector2Array literal isn't a constant
# expression, but a static var is built once at class load and is just as
# shareable across scripts (BlockSkins._RR_UNIT).
static var _RR_UNIT : PackedVector2Array = PackedVector2Array([
	Vector2(-1.0, 0.0), Vector2(-0.8660254, -0.5), Vector2(-0.5, -0.8660254), Vector2(0.0, -1.0),
	Vector2(0.0, -1.0), Vector2(0.5, -0.8660254), Vector2(0.8660254, -0.5), Vector2(1.0, 0.0),
	Vector2(1.0, 0.0), Vector2(0.8660254, 0.5), Vector2(0.5, 0.8660254), Vector2(0.0, 1.0),
	Vector2(0.0, 1.0), Vector2(-0.5, 0.8660254), Vector2(-0.8660254, 0.5), Vector2(-1.0, 0.0),
])

# 8x8 pixel sprites for the RETRO skin ('X' = filled). Shading is automatic:
# top-edge pixels get lit, bottom-edge pixels get shaded, plus a black outline.
const RETRO_SPRITES : Array = [
	[   # heart
		"........",
		".XX..XX.",
		"XXXXXXXX",
		"XXXXXXXX",
		".XXXXXX.",
		"..XXXX..",
		"...XX...",
		"........"],
	[   # star
		"...XX...",
		"...XX...",
		"..XXXX..",
		"XXXXXXXX",
		".XXXXXX.",
		"..XXXX..",
		".XX..XX.",
		"........"],
	[   # gem
		"........",
		"..XXXX..",
		".XXXXXX.",
		"XXXXXXXX",
		".XXXXXX.",
		"..XXXX..",
		"...XX...",
		"........"],
	[   # coin (stamped centre)
		"..XXXX..",
		".XXXXXX.",
		"XXXXXXXX",
		"XXX..XXX",
		"XXX..XXX",
		"XXXXXXXX",
		".XXXXXX.",
		"..XXXX.."],
	[   # lightning bolt
		"...XXX..",
		"..XXX...",
		".XXXX...",
		"XXXXXX..",
		"..XXX...",
		".XXX....",
		".XX.....",
		"X......."],
]

# Representative piece shapes for menu backgrounds
const DEMO_SHAPES : Array = [
	[[0, 0]],
	[[0, 0], [1, 0]],
	[[0, 0], [0, 1]],
	[[0, 0], [1, 0], [2, 0]],
	[[0, 0], [1, 0], [0, 1], [1, 1]],
	[[0, 0], [1, 0], [0, 1]],
	[[1, 0], [0, 1], [1, 1]],
	[[0, 0], [1, 0], [2, 0], [1, 1]],
	[[1, 0], [2, 0], [0, 1], [1, 1]],
	[[0, 0], [1, 0], [1, 1], [1, 2]],
]

# glow (0..1): set while the block is part of a match preview — skins that
# support it (circuit) light up their detail work.
# pr: the block's RESTING rect — canvas-continuous skins (honey/sakura/metals)
# derive their pattern scale from it so squash/stretch animations don't
# momentarily resize the shared pattern and tear it against neighbours.
static func paint(ci: CanvasItem, style: int, r: Rect2, col: Color, seed_v: int = 0, glow: float = 0.0, pr: Rect2 = Rect2(), with_overlay: bool = true) -> void:
	var s   := r.size.x
	var rad := s * 0.16
	if pr.size.x <= 0.0:
		pr = r
	match style:
		0:  _pastel(ci, r, col, s, rad)
		1:  _neon(ci, r, col, s, rad)
		2:  _circuit(ci, r, col, s, rad, seed_v, glow)
		3:  _brick(ci, r, col, s, rad, seed_v)
		4:  _crystal(ci, r, col, s, rad, seed_v)
		5:  _candy(ci, r, col, s, rad, seed_v)
		6:  _frost(ci, r, col, s, rad, seed_v)
		7:  _grass(ci, r, col, s, rad, seed_v, glow)
		8:  _water(ci, r, col, s, rad, seed_v)
		9:  _lava(ci, r, col, s, rad, seed_v)
		10: _wood(ci, r, col, s, rad, seed_v)
		11: _galaxy(ci, r, col, s, rad, seed_v)
		12: _honey(ci, r, col, s, rad, seed_v, pr)
		13: _retro(ci, r, col, s, rad, seed_v)
		14: _bubble(ci, r, col, s, rad, seed_v)
		15: _storm(ci, r, col, s, rad, seed_v)
		16: _sakura(ci, r, col, s, rad, seed_v, pr)
		17: _gold(ci, r, col, s, rad, seed_v, pr)
		18: _slime(ci, r, col, s, rad, seed_v)
		19: _disco(ci, r, col, s, rad, seed_v)
		20: _aurora(ci, r, col, s, rad, seed_v, pr)
		21: _plasma(ci, r, col, s, rad, seed_v)
		22: _marble(ci, r, col, s, rad, seed_v, pr)
		23: _matrix(ci, r, col, s, rad, seed_v)
		24: _hologram(ci, r, col, s, rad, seed_v)
		25: _prism(ci, r, col, s, rad, seed_v, pr)
		26: _stained(ci, r, col, s, rad, seed_v, pr)
		27: _synthwave(ci, r, col, s, rad, seed_v)
		28: _autumn(ci, r, col, s, rad, seed_v, pr)
		29: _warp(ci, r, col, s, rad, seed_v)
		30: _cat(ci, r, col, s, rad, seed_v)
	if with_overlay and OVERLAY_STYLES.has(style):
		paint_overlay(ci, style, r, col, seed_v)

# ── Polygon clipping (Sutherland–Hodgman vs axis-aligned rect) ────────────────
# Lets cross-block animations (sakura petals, metal gleams) be drawn by every
# block they touch while staying EXACTLY inside each block's bounds.
static func clip_poly_to_rect(pts: PackedVector2Array, r: Rect2) -> PackedVector2Array:
	var out := pts
	for edge in 4:
		if out.size() < 3:
			return PackedVector2Array()
		var inp := out
		out = PackedVector2Array()
		for i in inp.size():
			var a := inp[i]
			var b := inp[(i + 1) % inp.size()]
			var a_in := _inside_edge(a, r, edge)
			var b_in := _inside_edge(b, r, edge)
			if a_in:
				out.append(a)
				if not b_in:
					out.append(_isect_edge(a, b, r, edge))
			elif b_in:
				out.append(_isect_edge(a, b, r, edge))
	return out

# draw_polygon triangulates internally and errors ("triangulation failed") on
# degenerate input: zero-area slivers, duplicate/collinear points, or a self-
# intersecting outline. Clipped patterns hit all three at block edges. Pre-check
# with the same ear-clipping triangulator and silently skip if it can't be drawn.
static func draw_poly_safe(ci: CanvasItem, pts: PackedVector2Array, col: Color, assume_convex: bool = false) -> void:
	if pts.size() < 3:
		return
	# Convex callers (hex/diamond tiles) skip the costly triangulation pre-check —
	# a cheap shoelace area test is enough to drop degenerate slivers safely.
	if assume_convex:
		var area := 0.0
		for i in pts.size():
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			area += a.x * b.y - b.x * a.y
		if absf(area) < 2.0:
			return
		_cbuf[0] = col
		ci.draw_polygon(pts, _cbuf)
		return
	# Triangulate ONCE and submit the indexed triangles directly. draw_polygon
	# would triangulate a second time internally, so this halves the per-poly
	# triangulation cost for the continuous-pattern skins (petals, ribbons,
	# veins) that draw many clipped polys per cell every frame. Same skip
	# behaviour on degenerate input (empty index list = nothing drawn).
	var idx := Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		return
	var n := pts.size()
	if _tribuf.size() != n:
		_tribuf.resize(n)
	_tribuf.fill(col)
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, _tribuf)

static func _inside_edge(p: Vector2, r: Rect2, e: int) -> bool:
	match e:
		0: return p.x >= r.position.x
		1: return p.x <= r.end.x
		2: return p.y >= r.position.y
		_: return p.y <= r.end.y

static func _isect_edge(a: Vector2, b: Vector2, r: Rect2, e: int) -> Vector2:
	var k : float
	match e:
		0:
			k = (r.position.x - a.x) / (b.x - a.x)
			return Vector2(r.position.x, a.y + (b.y - a.y) * k)
		1:
			k = (r.end.x - a.x) / (b.x - a.x)
			return Vector2(r.end.x, a.y + (b.y - a.y) * k)
		2:
			k = (r.position.y - a.y) / (b.y - a.y)
			return Vector2(a.x + (b.x - a.x) * k, r.position.y)
		_:
			k = (r.end.y - a.y) / (b.y - a.y)
			return Vector2(a.x + (b.x - a.x) * k, r.end.y)

# ── Rounded helpers ───────────────────────────────────────────────────────────
static func rr_points(r: Rect2, rad: float) -> PackedVector2Array:
	# Leave at least a 1px straight edge on the short side. A radius of exactly
	# half the dimension makes opposite corner arcs share a point, producing a
	# degenerate polygon that fails triangulation (e.g. candy's thin gloss bar).
	rad = minf(rad, maxf((minf(r.size.x, r.size.y) - 1.0) * 0.5, 0.0))
	# Corner centres: TL, TR, BR, BL (4 arc points each, from the const dirs)
	var c0 := Vector2(r.position.x + rad, r.position.y + rad)
	var c1 := Vector2(r.end.x - rad,      r.position.y + rad)
	var c2 := Vector2(r.end.x - rad,      r.end.y - rad)
	var c3 := Vector2(r.position.x + rad, r.end.y - rad)
	var pts := PackedVector2Array()
	pts.resize(16)
	for i in 4:
		pts[i]      = c0 + _RR_UNIT[i] * rad
		pts[4 + i]  = c1 + _RR_UNIT[4 + i] * rad
		pts[8 + i]  = c2 + _RR_UNIT[8 + i] * rad
		pts[12 + i] = c3 + _RR_UNIT[12 + i] * rad
	return pts

# Degenerate guard: rects under ~6px collapse the corner arcs into invalid
# polygons (menu fallers paint at ~10px cells) — fall back to plain rects
static func rr_fill(ci: CanvasItem, r: Rect2, rad: float, col: Color) -> void:
	if r.size.x < 6.0 or r.size.y < 6.0:
		ci.draw_rect(r, col, true)
		return
	_cbuf[0] = col
	ci.draw_polygon(rr_points(r, rad), _cbuf)

static func rr_outline(ci: CanvasItem, r: Rect2, rad: float, col: Color, width: float) -> void:
	if r.size.x < 6.0 or r.size.y < 6.0:
		ci.draw_rect(r, col, false, width)
		return
	var pts := rr_points(r, rad)
	pts.append(pts[0])
	ci.draw_polyline(pts, col, width)

static func rr_grad(ci: CanvasItem, r: Rect2, rad: float, top_col: Color, bot_col: Color) -> void:
	if r.size.x < 6.0 or r.size.y < 6.0:
		ci.draw_rect(r, top_col.lerp(bot_col, 0.5), true)
		return
	var pts := rr_points(r, rad)
	var n := pts.size()
	if _gradbuf.size() != n:
		_gradbuf.resize(n)
	var inv_h := 1.0 / r.size.y
	for i in n:
		_gradbuf[i] = top_col.lerp(bot_col, clampf((pts[i].y - r.position.y) * inv_h, 0.0, 1.0))
	ci.draw_polygon(pts, _gradbuf)

# ── 0 PASTEL ──────────────────────────────────────────────────────────────────
static func _pastel(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float) -> void:
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.18))
	rr_grad(ci, r, rad, col.lightened(0.50), col.lightened(0.10))
	rr_outline(ci, r, rad, col.darkened(0.15), 1.5)
	ci.draw_circle(r.position + r.size * 0.26, s * 0.10, col.lightened(0.80))

# ── 1 NEON ────────────────────────────────────────────────────────────────────
static func _neon(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float) -> void:
	rr_fill(ci, r.grow(s * 0.18), rad + s * 0.14, Color(col.r, col.g, col.b, 0.05))
	rr_fill(ci, r.grow(s * 0.09), rad + s * 0.07, Color(col.r, col.g, col.b, 0.12))
	rr_fill(ci, r.grow(s * 0.05), rad + s * 0.04, Color(col.r, col.g, col.b, 0.22))
	rr_fill(ci, r, rad, col.darkened(0.82))
	rr_outline(ci, r, rad, col, 2.0)

# ── 2 CIRCUIT (animated) ──────────────────────────────────────────────────────
# Traces run edge-to-edge at fixed fractions, so neighbouring blocks form one
# continuous circuit. Solder pads at junctions, a seeded SMD chip, and a data
# pulse travelling the traces. `glow` (match preview) lights the whole net up.
static func _circuit(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int, glow: float = 0.0) -> void:
	var t := Time.get_ticks_msec() * 0.001
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.05, s * 0.05), r.size + Vector2(s * 0.05, s * 0.05)), rad, Color(0, 0, 0, 0.40))
	rr_grad(ci, r, rad, col.darkened(0.18 - glow * 0.10), col.darkened(0.42 - glow * 0.10))
	rr_outline(ci, r, rad, col.lightened(0.30 + glow * 0.30), 1.5 + glow)
	# Traces — same fractions on every block => they connect across the board
	var tc := Color(col.lightened(glow * 0.5).r, col.lightened(glow * 0.5).g,
		col.lightened(glow * 0.5).b, 0.50 + glow * 0.50)
	var tw := 1.2 + glow * 1.2
	var y1 := r.position.y + r.size.y * 0.30
	var y2 := r.position.y + r.size.y * 0.70
	var x1 := r.position.x + r.size.x * 0.50
	ci.draw_line(Vector2(r.position.x, y1), Vector2(r.end.x, y1), tc, tw)
	ci.draw_line(Vector2(r.position.x, y2), Vector2(r.end.x, y2), tc, tw)
	ci.draw_line(Vector2(x1, r.position.y), Vector2(x1, r.end.y), tc, tw)
	# Solder pads at the junctions
	for jy in [y1, y2]:
		ci.draw_circle(Vector2(x1, jy), s * 0.055 + glow * s * 0.02, col.lightened(0.55 + glow * 0.25))
		ci.draw_circle(Vector2(x1, jy), s * 0.025, col.darkened(0.45))
	# Seeded SMD chip on one of four spots, legs reaching the nearest trace
	var spots := [Vector2(0.22, 0.50), Vector2(0.78, 0.50), Vector2(0.25, 0.14), Vector2(0.72, 0.86)]
	var sp : Vector2 = r.position + r.size * spots[seed_v % 4]
	var chip := Rect2(sp - Vector2(s * 0.07, s * 0.05), Vector2(s * 0.14, s * 0.10))
	ci.draw_rect(chip, Color(0.08, 0.08, 0.10), true)
	ci.draw_rect(chip, col.lightened(0.20), false, 1.0)
	for leg in 3:
		var lx := chip.position.x + s * 0.025 + float(leg) * s * 0.045
		ci.draw_line(Vector2(lx, chip.position.y - s * 0.03), Vector2(lx, chip.position.y), tc, 1.0)
		ci.draw_line(Vector2(lx, chip.end.y), Vector2(lx, chip.end.y + s * 0.03), tc, 1.0)
	# Data pulse riding the traces — constant speed (a glow-scaled speed makes
	# the dot teleport, since position = time × speed); glow brightens it instead
	var k := fmod(t * 0.45 + float(seed_v % 23) * 0.13, 1.0)
	var pp : Vector2
	if k < 0.5:   # along the top trace, left -> right
		pp = Vector2(lerpf(r.position.x, r.end.x, k * 2.0), y1)
	else:         # down the vertical, then it wraps
		pp = Vector2(x1, lerpf(y1, r.end.y, (k - 0.5) * 2.0))
	ci.draw_circle(pp, s * 0.045, Color(1, 1, 1, 0.55 + glow * 0.40))
	ci.draw_circle(pp, s * 0.09, Color(col.lightened(0.5).r, col.lightened(0.5).g, col.lightened(0.5).b, 0.22 + glow * 0.30))

# ── 3 BRICK (running-bond wall) ───────────────────────────────────────────────
static func _brick(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.05, s * 0.07), r.size), rad, Color(0, 0, 0, 0.35))
	rr_fill(ci, r, rad, col.darkened(0.62))
	var rh := (r.size.y - s * 0.05) / 3.0
	var bi := 0
	for row in 3:
		var y := r.position.y + s * 0.025 + float(row) * rh
		var edges : Array = [0.0, 0.5, 1.0] if row % 2 == 0 else [0.0, 0.25, 0.75, 1.0]
		for i in edges.size() - 1:
			var x0 : float = r.position.x + s * 0.025 + edges[i]     * (r.size.x - s * 0.05)
			var x1 : float = r.position.x + s * 0.025 + edges[i + 1] * (r.size.x - s * 0.05)
			var shade := float((seed_v * 13 + bi * 37) % 5) * 0.035
			var brick := Rect2(x0 + s * 0.02, y + s * 0.02, x1 - x0 - s * 0.04, rh - s * 0.04)
			rr_fill(ci, brick, s * 0.05, col.darkened(0.05 + shade))
			ci.draw_rect(Rect2(brick.position, Vector2(brick.size.x, s * 0.045)), col.lightened(0.18), true)
			# Weathering: texture specks on every brick, a crack on the odd one
			for sp in 2:
				var px := brick.position.x + float((seed_v * 17 + bi * 29 + sp * 41) % 100) / 100.0 * brick.size.x
				var py := brick.position.y + s * 0.06 + float((seed_v * 23 + bi * 31 + sp * 53) % 100) / 100.0 * (brick.size.y - s * 0.08)
				ci.draw_circle(Vector2(px, py), s * 0.014, col.darkened(0.30 + shade))
			if (seed_v + bi * 7) % 9 == 0:
				var cx := brick.get_center()
				ci.draw_line(cx + Vector2(-s * 0.05, -s * 0.03), cx + Vector2(0, s * 0.02), col.darkened(0.50), 1.0)
				ci.draw_line(cx + Vector2(0, s * 0.02), cx + Vector2(s * 0.05, s * 0.045), col.darkened(0.50), 1.0)
			bi += 1
	# Moss tuft creeping out of the mortar on some blocks
	if seed_v % 6 == 0:
		var mp := r.position + r.size * Vector2(0.20 + float(seed_v % 3) * 0.25, 0.36)
		for m in 3:
			ci.draw_circle(mp + Vector2(float(m - 1) * s * 0.035, float(m % 2) * s * 0.02),
				s * 0.030, Color(0.45, 0.65, 0.30, 0.55))
	rr_outline(ci, r, rad, col.darkened(0.40), 1.5)

# ── 4 CRYSTAL (v4: the block IS a cut gem — octagonal emerald cut) ───────────
static func _crystal(ci: CanvasItem, r: Rect2, col: Color, s: float, _rad: float, _seed_v: int = 0) -> void:
	var cut := s * 0.24
	var oct := PackedVector2Array([
		Vector2(r.position.x + cut, r.position.y),
		Vector2(r.end.x - cut, r.position.y),
		Vector2(r.end.x, r.position.y + cut),
		Vector2(r.end.x, r.end.y - cut),
		Vector2(r.end.x - cut, r.end.y),
		Vector2(r.position.x + cut, r.end.y),
		Vector2(r.position.x, r.end.y - cut),
		Vector2(r.position.x, r.position.y + cut),
	])
	# Drop shadow (same octagon, offset)
	var sh := PackedVector2Array()
	for p in oct:
		sh.append(p + Vector2(s * 0.03, s * 0.06))
	ci.draw_polygon(sh, PackedColorArray([Color(0, 0, 0, 0.30)]))
	# Rim gradient — lit from above
	var rim_cols := PackedColorArray()
	for p in oct:
		rim_cols.append(col.lightened(0.30).lerp(col.darkened(0.28),
			clampf((p.y - r.position.y) / r.size.y, 0.0, 1.0)))
	ci.draw_polygon(oct, rim_cols)
	# Inner table — the flat bright face of the gem
	var c := r.get_center()
	var table := PackedVector2Array()
	for p in oct:
		table.append(c + (p - c) * 0.54)
	var table_cols := PackedColorArray()
	for p in table:
		table_cols.append(col.lightened(0.60).lerp(col.lightened(0.18),
			clampf((p.y - r.position.y) / r.size.y, 0.0, 1.0)))
	ci.draw_polygon(table, table_cols)
	# Facet edges from rim corners to table corners
	for i in oct.size():
		ci.draw_line(oct[i], table[i], Color(1, 1, 1, 0.22), 1.0)
	# Outlines
	var oct_closed := oct.duplicate(); oct_closed.append(oct[0])
	ci.draw_polyline(oct_closed, col.lightened(0.45), 1.5)
	var tbl_closed := table.duplicate(); tbl_closed.append(table[0])
	ci.draw_polyline(tbl_closed, Color(1, 1, 1, 0.40), 1.0)
	# Glint stroke across the table + a sparkle dot
	ci.draw_line(c + Vector2(-s * 0.14, -s * 0.06), c + Vector2(-s * 0.04, -s * 0.16),
		Color(1, 1, 1, 0.75), 2.0)
	ci.draw_circle(c + Vector2(s * 0.12, s * 0.10), s * 0.030, Color(1, 1, 1, 0.65))

# ── 5 CANDY (candy cane: diagonal stripes in the piece colour over white) ────
static func _candy(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, _seed_v: int = 0) -> void:
	var crad := rad + s * 0.07
	var stripe := col.lerp(Color(0.95, 0.15, 0.20), 0.35)   # nudge toward candy red
	var white := Color(1.0, 0.97, 0.95)
	rr_fill(ci, Rect2(r.position + Vector2(0, s * 0.07), r.size), crad, Color(0, 0, 0, 0.30))
	# White peppermint base
	rr_grad(ci, r, crad, white, Color(0.90, 0.86, 0.87))
	# Diagonal coloured stripes, anchored to the block corner so every candy
	# looks identical; clipped just inside the rounded edge
	var inner := r.grow(-s * 0.05)
	var sw := s * 0.24
	var y0 := r.position.y - s * 0.1
	var y1 := r.end.y + s * 0.1
	var base := r.position.x + r.position.y
	var lo := -sw
	while lo < r.size.x + r.size.y + sw:
		var d := base + lo
		var poly := clip_poly_to_rect(PackedVector2Array([
			Vector2(d - y0, y0), Vector2(d + sw - y0, y0),
			Vector2(d + sw - y1, y1), Vector2(d - y1, y1)]), inner)
		draw_poly_safe(ci, poly, stripe)
		lo += sw * 2.0
	# Glossy shine across the top + a little sparkle
	var gloss := Rect2(r.position + Vector2(r.size.x * 0.12, r.size.y * 0.09),
		Vector2(r.size.x * 0.60, r.size.y * 0.18))
	rr_fill(ci, gloss, gloss.size.y * 0.5, Color(1, 1, 1, 0.45))
	ci.draw_circle(r.position + r.size * Vector2(0.78, 0.74), s * 0.045, Color(1, 1, 1, 0.40))
	rr_outline(ci, r, crad, stripe.darkened(0.35), 2.0)

# ── 6 FROST ───────────────────────────────────────────────────────────────────
static func _frost(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	var ice := col.lerp(Color(0.65, 0.85, 1.0), 0.40)
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.25))
	rr_grad(ci, r, rad,
		Color(ice.lightened(0.40).r, ice.lightened(0.40).g, ice.lightened(0.40).b, 0.92),
		Color(ice.darkened(0.10).r,  ice.darkened(0.10).g,  ice.darkened(0.10).b,  0.88))
	# Seeded cracks
	var h := seed_v * 2654435761
	for i in 3:
		h = int(fmod(float(h) * 1103515.0 + 12345.0, 2147483647.0))
		var x0 : float = r.position.x + s * 0.11 + float(h % 100) / 100.0 * (r.size.x - s * 0.32)
		var y0 : float = r.position.y + s * 0.11 + float((h / 100) % 100) / 100.0 * (r.size.y - s * 0.32)
		var dx : float = (float((h / 7) % 17) - 8.0) * s * 0.027
		var dy : float = (float((h / 11) % 17) - 8.0) * s * 0.027
		var p0 := Vector2(x0, y0)
		var p1 := p0 + Vector2(dx, dy)
		ci.draw_line(p0, p1, Color(1, 1, 1, 0.40), 1.0)
		ci.draw_line(p1, p1 + Vector2(dy * 0.5, -dx * 0.5), Color(1, 1, 1, 0.25), 1.0)
	var band := Rect2(r.position + Vector2(s * 0.09, s * 0.07), Vector2(r.size.x - s * 0.18, s * 0.11))
	rr_fill(ci, band, s * 0.05, Color(1, 1, 1, 0.45))
	# Icicles hanging from the frosted edge (seeded count + lengths)
	for i in 2 + seed_v % 2:
		var ix := r.position.x + s * (0.20 + 0.28 * float(i)) + float((seed_v * 13 + i * 29) % 8) * s * 0.012
		var il := s * (0.10 + float((seed_v * 19 + i * 37) % 10) * 0.014)
		ci.draw_polygon(PackedVector2Array([
			Vector2(ix - s * 0.035, band.end.y), Vector2(ix, band.end.y + il),
			Vector2(ix + s * 0.035, band.end.y)]),
			PackedColorArray([Color(1, 1, 1, 0.38)]))
	# A frost sparkle that twinkles in and out
	var t := Time.get_ticks_msec() * 0.001
	var tw := absf(sin(t * 1.4 + float(seed_v % 13) * 0.8))
	var spx := r.position + r.size * Vector2(0.30 + float(seed_v % 4) * 0.13, 0.55 + float(seed_v % 3) * 0.10)
	ci.draw_line(spx + Vector2(-s * 0.05, 0), spx + Vector2(s * 0.05, 0), Color(1, 1, 1, 0.65 * tw), 1.0)
	ci.draw_line(spx + Vector2(0, -s * 0.05), spx + Vector2(0, s * 0.05), Color(1, 1, 1, 0.65 * tw), 1.0)
	rr_outline(ci, r.grow(-s * 0.045), rad - s * 0.034, Color(1, 1, 1, 0.30), 1.0)
	rr_outline(ci, r, rad, ice.lightened(0.55), 1.5)

# ── 7 GRASS ───────────────────────────────────────────────────────────────────
# Grass tones: greens with the occasional pink — replaces the muddy grey/brown the
# old col.lerp produced for the grey/orange pieces. Picked per piece-colour.
# Wildflower-meadow palette: greens dominate, with a harmonious spread of SOFT
# pastels so colour blocks read as a flowery patchwork, not jarring pink spots.
const GRASS_TONES : Array = [
	Color(0.38, 0.78, 0.42),   # green
	Color(0.45, 0.81, 0.44),   # green
	Color(0.33, 0.72, 0.44),   # deep green
	Color(0.52, 0.83, 0.47),   # bright green
	Color(0.41, 0.77, 0.50),   # mint green
	Color(0.48, 0.80, 0.40),   # lime green
	Color(0.58, 0.82, 0.52),   # soft yellow-green
	Color(0.35, 0.74, 0.57),   # teal-green
	Color(0.44, 0.79, 0.46),   # green
	Color(0.87, 0.68, 0.79),   # soft pink
	Color(0.78, 0.76, 0.91),   # soft lavender
	Color(0.91, 0.86, 0.62),   # soft buttercup
	Color(0.56, 0.85, 0.77),   # soft turquoise
]

static func _grass(ci: CanvasItem, r: Rect2, _col: Color, s: float, rad: float, seed_v: int, glow: float = 0.0) -> void:
	# Tone keyed off the stable per-cell seed (NOT col): col pulses during the clear
	# preview, which made a colour-hash flicker between palette entries every frame.
	var g : Color = GRASS_TONES[posmod(seed_v, GRASS_TONES.size())]
	if glow > 0.0:
		g = g.lightened(glow * 0.40)   # clear-preview highlight (was carried by the pulsing col)
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.25))
	rr_grad(ci, r, rad, g.lightened(0.25), g.darkened(0.28))
	var t := Time.get_ticks_msec() * 0.001
	var n_blades := 6
	for i in n_blades:
		var bx : float = r.position.x + s * 0.09 + float(i) * (r.size.x - s * 0.18) / float(n_blades - 1)
		var bh : float = s * (0.14 + float((seed_v * 7 + i * 11) % 5) * 0.036)
		# Blades sway gently in the breeze, each on its own phase
		var lean : float = float((seed_v + i * 3) % 5 - 2) * s * 0.027 \
			+ sin(t * 1.6 + float(seed_v % 9) * 0.7 + float(i) * 0.9) * s * 0.030
		ci.draw_polygon(PackedVector2Array([
			Vector2(bx - s * 0.045, r.position.y + s * 0.20),
			Vector2(bx + lean, r.position.y + s * 0.20 - bh),
			Vector2(bx + s * 0.045, r.position.y + s * 0.20)]),
			PackedColorArray([g.lightened(0.35 if i % 2 == 0 else 0.15)]))
	# Pollen speckles
	for i in 3:
		var px : float = r.position.x + s * 0.14 + float((seed_v * 31 + i * 53) % 100) / 100.0 * (r.size.x - s * 0.28)
		var py : float = r.position.y + r.size.y * 0.45 + float((seed_v * 17 + i * 29) % 100) / 100.0 * (r.size.y * 0.4)
		ci.draw_circle(Vector2(px, py), s * 0.034, g.lightened(0.40))
	_grass_flowers(ci, r, s, seed_v)
	rr_outline(ci, r, rad, g.darkened(0.35), 1.5)

# Flowers: varied colour + position, on many (not all) blocks — denser than the old
# 1-in-7-at-a-fixed-spot version.
static func _grass_flowers(ci: CanvasItem, r: Rect2, s: float, seed_v: int) -> void:
	# Weighted toward PINK, with TURQUOISE accents (per Jay's request) — a few
	# white/amber kept for variety
	var fcols : Array = [
		Color(1.0, 0.55, 0.74), Color(1.0, 0.44, 0.70), Color(1.0, 0.70, 0.84),
		Color(1.0, 0.60, 0.80), Color(1.0, 0.50, 0.76),     # pinks (weighted)
		Color(0.26, 0.88, 0.82), Color(0.40, 0.93, 0.87),   # turquoise
		Color(1, 1, 1), Color(1.0, 0.82, 0.45),             # white + amber
	]
	var count := 0
	if seed_v % 5 < 3: count = 1          # ~60% of blocks get a flower
	if seed_v % 5 == 0: count = 2          # ~20% get a second one
	for f in count:
		var sv := seed_v * (f + 1) * 41 + f * 17
		var fcol : Color = fcols[sv % fcols.size()]
		var fp := r.position + Vector2(s * (0.20 + float(sv % 60) / 100.0),
			s * (0.20 + float((sv / 7) % 60) / 100.0))
		var pr : float = s * (0.045 + float(sv % 3) * 0.006)
		for i in 5:
			var a := float(i) / 5.0 * TAU + float(sv % 6)
			ci.draw_circle(fp + Vector2(cos(a), sin(a)) * pr * 1.5, pr, fcol)
		ci.draw_circle(fp, pr * 0.85, Color(0.98, 0.85, 0.25))

# ── 8 WATER (animated) ────────────────────────────────────────────────────────
static func _water(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var ph := float(seed_v) * 0.7
	var shallow := col.lerp(Color(0.32, 0.74, 1.00), 0.68)
	var deep := col.lerp(Color(0.03, 0.20, 0.52), 0.80)
	# Drop shadow
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.25))
	# Body — bright near the surface, deep blue toward the bottom
	rr_grad(ci, r, rad, shallow.lightened(0.12), deep)
	# Caustic light ripples dancing under the surface
	for c in 2:
		var cy : float = r.position.y + r.size.y * (0.50 + 0.26 * float(c))
		var pts := PackedVector2Array()
		for i in 9:
			var fx : float = float(i) / 8.0
			var x : float = r.position.x + fx * r.size.x
			var y : float = cy + sin(t * 1.9 + ph + fx * 7.0 + float(c) * 1.7) * s * 0.045
			pts.append(Vector2(x, y))
		ci.draw_polyline(pts, Color(0.75, 0.95, 1.0, 0.18 - 0.06 * float(c)), 1.5)
	# Surface — a glassy rippling waterline near the top
	var surf_y : float = r.position.y + r.size.y * 0.20
	var n := 8
	var top := PackedVector2Array()
	for i in n + 1:
		var fx : float = float(i) / float(n)
		var x : float = r.position.x + fx * r.size.x
		var y : float = surf_y + sin(t * 2.4 + ph + fx * 6.5) * s * 0.040
		top.append(Vector2(x, y))
	var ribbon := top.duplicate()
	for i in range(n, -1, -1):
		ribbon.append(Vector2(top[i].x, top[i].y + s * 0.08))
	ribbon = clip_poly_to_rect(ribbon, r)
	draw_poly_safe(ci, ribbon, Color(1, 1, 1, 0.20))
	ci.draw_polyline(top, Color(1, 1, 1, 0.55), 1.5)
	# Rising bubbles — sway as they climb, shrink and fade near the surface
	for i in 3:
		var bk : float = fmod(t * (0.20 + float(i) * 0.07) + float(seed_v % 7 + i * 3) * 0.17, 1.0)
		var bx : float = r.position.x + r.size.x * (0.26 + 0.46 * float((seed_v + i * 5) % 3) / 2.0) \
			+ sin(t * 2.4 + float(i) * 2.0) * s * 0.045
		var by : float = lerpf(r.end.y - s * 0.08, surf_y + s * 0.04, bk)
		var br : float = s * (0.022 + float(i) * 0.010) * (1.0 - bk * 0.4)
		var ba : float = 0.42 * (1.0 - bk * 0.5)
		ci.draw_circle(Vector2(bx, by), br, Color(0.85, 0.96, 1.0, ba))
		ci.draw_circle(Vector2(bx - br * 0.3, by - br * 0.3), br * 0.4, Color(1, 1, 1, ba * 0.9))
	# Specular glint sliding across the surface
	var gx : float = r.position.x + s * 0.16 + fmod(t * s * 0.18 + float(seed_v % 13) * 3.7, r.size.x - s * 0.32)
	ci.draw_circle(Vector2(gx, surf_y - s * 0.02), s * 0.05, Color(1, 1, 1, 0.30))
	rr_outline(ci, r, rad, shallow.lightened(0.30), 1.5)

# ── 9 LAVA (animated) ─────────────────────────────────────────────────────────
static func _lava(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var pulse := 0.5 + 0.5 * sin(t * 2.3 + float(seed_v % 9) * 0.8)
	var hot := col.lerp(Color(1.00, 0.42, 0.04), 0.78)
	# Drop shadow
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.40))
	# Molten base — this is what glows through the cracks and the rim seam
	rr_grad(ci, r, rad,
		Color(1.0, 0.82, 0.28).lerp(hot, 0.35 + pulse * 0.25),
		hot.darkened(0.20))
	# Cooled basalt crust on top, inset so a glowing seam rings the edge
	var crust := r.grow(-s * 0.07)
	rr_grad(ci, crust, rad * 0.7,
		Color(0.16, 0.07, 0.05).lerp(Color(0.26, 0.12, 0.08), pulse * 0.5),
		Color(0.08, 0.03, 0.02))
	# Glowing molten veins, drawn halo -> body -> hot core. Both run edge-to-edge
	# at fixed fractions so the cracks line up across neighbouring blocks; the
	# waypoint jitters per seed so no two blocks crack the same way.
	var halo := Color(1.0, 0.35, 0.05, 0.30 + pulse * 0.30)
	var body := Color(1.0, 0.55, 0.12, 0.55 + pulse * 0.40)
	var core := Color(1.0, 0.90, 0.45, 0.65 + pulse * 0.35)
	var h := seed_v
	h = (h * 1103515 + 12345) % 2147483647
	var hy0 : float = r.position.y + r.size.y * 0.5
	var jm := Vector2(r.position.x + r.size.x * 0.5,
		r.position.y + r.size.y * (0.30 + float(h % 100) / 100.0 * 0.40))
	var hv := PackedVector2Array([Vector2(r.position.x, hy0), jm, Vector2(r.end.x, hy0)])
	h = (h * 1103515 + 12345) % 2147483647
	var vx0 : float = r.position.x + r.size.x * 0.5
	var jm2 := Vector2(r.position.x + r.size.x * (0.30 + float(h % 100) / 100.0 * 0.40),
		r.position.y + r.size.y * 0.5)
	var vv := PackedVector2Array([Vector2(vx0, r.position.y), jm2, Vector2(vx0, r.end.y)])
	for v : PackedVector2Array in [hv, vv]:
		ci.draw_polyline(v, halo, s * 0.11)
		ci.draw_polyline(v, body, s * 0.055)
		ci.draw_polyline(v, core, s * 0.022)
	# A bright glob of magma flowing along the horizontal crack
	var fk : float = fmod(t * 0.4 + float(seed_v % 17) * 0.11, 1.0)
	var flow : Vector2
	if fk < 0.5:
		flow = hv[0].lerp(hv[1], fk * 2.0)
	else:
		flow = hv[1].lerp(hv[2], (fk - 0.5) * 2.0)
	ci.draw_circle(flow, s * 0.05, Color(1.0, 0.95, 0.6, 0.5 + pulse * 0.3))
	ci.draw_circle(flow, s * 0.028, Color(1, 1, 0.85, 0.85))
	# Embers lifting off and fading
	for i in 2:
		var ek : float = fmod(t * (0.5 + float(i) * 0.13) + float(seed_v % 11 + i * 5) * 0.19, 1.0)
		var ex : float = r.position.x + r.size.x * (0.28 + 0.44 * float((seed_v + i * 3) % 3) / 2.0) \
			+ sin(t * 3.0 + float(i) * 2.0) * s * 0.05
		var ey : float = lerpf(r.end.y - s * 0.12, r.position.y + s * 0.10, ek)
		ci.draw_circle(Vector2(ex, ey), s * 0.018 * (1.0 - ek * 0.5),
			Color(1.0, 0.7, 0.25, 0.7 * (1.0 - ek)))
	rr_outline(ci, r, rad, Color(0.05, 0.02, 0.02, 0.9), 1.5)

# ── 10 WOOD ───────────────────────────────────────────────────────────────────
# End-grain log top (Minecraft style): bark rim around a cut face with
# concentric growth rings, slightly off-centre per block
static func _wood(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	var w := col.lerp(Color(0.62, 0.42, 0.22), 0.60)
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.30))
	# Bark rim
	rr_grad(ci, r, rad, w.darkened(0.28), w.darkened(0.48))
	# Bark notches around the rim
	for i in 4:
		var na := float(i) * PI * 0.5 + float(seed_v % 7) * 0.3 + 0.4
		var np2 := r.get_center() + Vector2(cos(na), sin(na)) * s * 0.47
		ci.draw_line(np2, np2 + (r.get_center() - np2).normalized() * s * 0.05, w.darkened(0.60), 2.0)
	# Cut face
	var face := r.grow(-s * 0.11)
	rr_grad(ci, face, rad * 0.65, w.lightened(0.32), w.lightened(0.06))
	# Growth rings — rounded, jittered off-centre, alternating shade
	var jit := Vector2(float(seed_v % 5 - 2), float((seed_v / 5) % 5 - 2)) * s * 0.016
	for i in 3:
		var k := 0.76 - float(i) * 0.23
		var ring := Rect2(face.position + face.size * (1.0 - k) * 0.5 + jit * (1.0 + float(i) * 0.5),
			face.size * k)
		rr_outline(ci, ring, maxf(rad * 0.5 * k, 2.0), w.darkened(0.25 + float(i % 2) * 0.08), 1.6)
	# Core
	var core := face.get_center() + jit * 2.4
	ci.draw_circle(core, s * 0.050, w.darkened(0.32))
	ci.draw_circle(core, s * 0.024, w.lightened(0.10))
	# Radial drying crack on some logs
	if seed_v % 3 == 0:
		var ca2 := float(seed_v % 11) * 0.6
		var dir2 := Vector2(cos(ca2), sin(ca2))
		ci.draw_line(core + dir2 * s * 0.07, core + dir2 * s * 0.34, w.darkened(0.45), 1.3)
	rr_outline(ci, r, rad, w.darkened(0.45), 1.5)

# ── 12 HONEY (animated: continuous honeycomb + oozing drip) ──────────────────
static func _honey(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, _seed_v: int, pr: Rect2 = Rect2()) -> void:
	var ps := pr.size.x if pr.size.x > 0.0 else s
	# Every piece colour maps to a SHADE OF AMBER (light wildflower to dark
	# buckwheat) — pieces stay tellable apart, nothing reads green/blue
	var tone := fmod(col.h * 2.7 + col.v * 0.5, 1.0)
	var hn := Color(1.00, 0.76, 0.28).lerp(Color(0.78, 0.48, 0.10), tone)
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.30))
	# Light base = the wax walls; the darker hex cells get drawn on top
	rr_grad(ci, r, rad, hn.lightened(0.35), hn.lightened(0.05))
	# Honeycomb tiled in ABSOLUTE canvas space — one continuous comb across
	# all neighbouring blocks, each cell clipped to its block
	var hs := ps * 0.27
	var hw := sqrt(3.0) * hs
	var vstep := 1.5 * hs
	var inner := r.grow(-s * 0.045)
	# Pattern-space translation: lattice is computed in pr-space and shifted by
	# delta — lets the dragged piece sample BOARD-space comb so the hover
	# preview matches the placed result exactly. Small deltas (squash wobble)
	# are zeroed so the pattern stays put during landing animations.
	var delta := r.position - pr.position
	if delta.length() < s * 0.5:
		delta = Vector2.ZERO
	var row0 := int(floor((pr.position.y - hs) / vstep))
	var row1 := int(ceil((pr.end.y + hs) / vstep))
	for row in range(row0, row1 + 1):
		var cy := float(row) * vstep
		var xoff := hw * 0.5 if posmod(row, 2) == 1 else 0.0
		var q0 := int(floor((pr.position.x - hw) / hw))
		var q1 := int(ceil((pr.end.x + hw) / hw))
		for q in range(q0, q1 + 1):
			var cx := float(q) * hw + xoff
			var hc := Vector2(cx, cy) + delta
			var hh := absi((q * 73856093) ^ (row * 19349663))
			var hex := PackedVector2Array()
			var fully_inside := true
			for i in 6:
				var a := PI / 6.0 + float(i) * PI / 3.0
				var pt := hc + Vector2(cos(a), sin(a)) * hs * 0.90
				hex.append(pt)
				if not inner.has_point(pt):
					fully_inside = false
			var cell := clip_poly_to_rect(hex, inner)
			draw_poly_safe(ci, cell, hn.darkened(0.22 + float(hh % 5) * 0.05), true)
			# Wax-capped cells (only when the whole hex fits inside the block)
			if fully_inside and hh % 3 == 0:
				ci.draw_circle(hc, hs * 0.58, hn.lightened(0.22))
				ci.draw_circle(hc - Vector2(hs * 0.18, hs * 0.18), hs * 0.16, hn.lightened(0.45))
	# Glossy shine band
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.10, s * 0.06), Vector2(r.size.x - s * 0.20, s * 0.09)),
		s * 0.045, Color(1, 1, 0.85, 0.30))
	rr_outline(ci, r, rad, hn.darkened(0.35), 1.5)

# Overlay pass: effects that hang below the block (drawn after all grid cells)
static func paint_overlay(ci: CanvasItem, style: int, r: Rect2, col: Color, seed_v: int = 0) -> void:
	var s := r.size.x
	var t := Time.get_ticks_msec() * 0.001
	match style:
		12:  # Honey drip: oozes down slowly, then retracts back up — no popping
			var tone := fmod(col.h * 2.7 + col.v * 0.5, 1.0)
			var hn := Color(1.00, 0.76, 0.28).lerp(Color(0.78, 0.48, 0.10), tone)
			var dk := fmod(t * 0.30 + float(seed_v % 9) * 0.13, 1.0)
			var dx := r.position.x + r.size.x * (0.30 + 0.40 * float(seed_v % 3) / 2.0)
			var k := (dk / 0.7) if dk < 0.7 else (1.0 - (dk - 0.7) / 0.3)
			if k > 0.02:
				var stretch := s * 0.16 * k
				var bulb := s * 0.05 * (0.55 + 0.45 * k)
				ci.draw_circle(Vector2(dx, r.end.y - s * 0.02), s * 0.045 * (0.55 + 0.45 * k), hn.lightened(0.15))
				ci.draw_line(Vector2(dx, r.end.y - s * 0.02), Vector2(dx, r.end.y + stretch), hn.lightened(0.15), s * 0.06 * (0.55 + 0.45 * k))
				ci.draw_circle(Vector2(dx, r.end.y + stretch), bulb, hn.lightened(0.20))
		18:  # Slime drip: same ooze-then-retract envelope
			var gl := col.lerp(Color(0.40, 0.90, 0.25), 0.55)
			var dk2 := fmod(t * 0.26 + float(seed_v % 6) * 0.15, 1.0)
			var k2 := (dk2 / 0.65) if dk2 < 0.65 else (1.0 - (dk2 - 0.65) / 0.35)
			if k2 > 0.02:
				var dx2 := r.position.x + r.size.x * (0.62 - 0.30 * float(seed_v % 2))
				var stretch2 := s * 0.14 * k2
				ci.draw_line(Vector2(dx2, r.end.y - s * 0.02), Vector2(dx2, r.end.y + stretch2), gl.darkened(0.05), s * 0.055 * (0.55 + 0.45 * k2))
				ci.draw_circle(Vector2(dx2, r.end.y + stretch2), s * 0.045 * (0.55 + 0.45 * k2), gl.lightened(0.10))

# ── 13 RETRO (v6: classic NES/Tetris bevelled block) ─────────────────────────
# The quintessential 8-bit game block: chunky dark border, solid colour face,
# a 3D pixel bevel (lit top-left, shaded bottom-right), the classic corner shine
# square, and faint CRT scanlines. Static — clean and cheap (all rects).
static func _retro(ci: CanvasItem, r: Rect2, col: Color, s: float, _rad: float, _seed_v: int) -> void:
	# Hard pixel shadow
	ci.draw_rect(Rect2(r.position + Vector2(s * 0.06, s * 0.06), r.size), Color(0, 0, 0, 0.35), true)
	# Dark outer border, then the solid colour face inset within it
	ci.draw_rect(r, col.darkened(0.55), true)
	var bw := s * 0.10
	var inner := Rect2(r.position + Vector2(bw, bw), r.size - Vector2(bw * 2.0, bw * 2.0))
	ci.draw_rect(inner, col, true)
	# 3D bevel: lit top + left edges, shaded bottom + right edges
	var e := s * 0.07
	var lite := col.lightened(0.45)
	var dark := col.darkened(0.32)
	ci.draw_rect(Rect2(inner.position, Vector2(inner.size.x, e)), lite, true)
	ci.draw_rect(Rect2(inner.position, Vector2(e, inner.size.y)), lite, true)
	ci.draw_rect(Rect2(Vector2(inner.position.x, inner.end.y - e), Vector2(inner.size.x, e)), dark, true)
	ci.draw_rect(Rect2(Vector2(inner.end.x - e, inner.position.y), Vector2(e, inner.size.y)), dark, true)
	# Classic corner shine square (top-left)
	ci.draw_rect(Rect2(inner.position + Vector2(s * 0.13, s * 0.13), Vector2(s * 0.15, s * 0.15)), col.lightened(0.75), true)
	# Faint CRT scanlines
	var y := r.position.y + s * 0.16
	while y < r.end.y - s * 0.05:
		ci.draw_line(Vector2(r.position.x + bw, y), Vector2(r.end.x - bw, y), Color(0, 0, 0, 0.10), 1.0)
		y += s * 0.20

# ── 14 BUBBLE (animated: iridescent soap film) ────────────────────────────────
static func _bubble(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	var t := Time.get_ticks_msec() * 0.001
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad + s * 0.06, Color(0, 0, 0, 0.18))
	# Glassy translucent body
	var body := Color(col.lightened(0.20).r, col.lightened(0.20).g, col.lightened(0.20).b, 0.38)
	rr_grad(ci, r, rad + s * 0.06,
		Color(col.lightened(0.45).r, col.lightened(0.45).g, col.lightened(0.45).b, 0.45), body)
	# Iridescent rim — hue drifts over time, each block out of phase
	var hue := fmod(col.h + 0.12 * sin(t * 0.9 + float(seed_v % 13) * 0.7), 1.0)
	if hue < 0.0: hue += 1.0
	var iri := Color.from_hsv(hue, 0.55, 1.0, 0.75)
	rr_outline(ci, r, rad + s * 0.06, iri, 2.0)
	rr_outline(ci, r.grow(-s * 0.05), rad, Color(1, 1, 1, 0.18), 1.0)
	# Crescent highlight top-left
	ci.draw_arc(r.position + r.size * Vector2(0.34, 0.34), s * 0.20, PI * 0.95, PI * 1.55, 12,
		Color(1, 1, 1, 0.75), 2.5, false)
	ci.draw_circle(r.position + r.size * Vector2(0.26, 0.24), s * 0.045, Color(1, 1, 1, 0.85))
	# Mini-bubbles drifting up inside, swaying — each one pops at the top
	for i in 3:
		var bk := fmod(t * (0.14 + float(i) * 0.05) + float((seed_v + i * 7) % 9) * 0.13, 1.0)
		var bx := r.position.x + r.size.x * (0.25 + 0.50 * float((seed_v * 3 + i * 5) % 4) / 3.0) \
			+ sin(t * 2.0 + float(i) * 2.2 + float(seed_v)) * s * 0.05
		var by := lerpf(r.end.y - s * 0.14, r.position.y + s * 0.16, bk)
		var brr := s * (0.028 + 0.020 * bk + float(i % 2) * 0.012)
		if bk < 0.86:
			ci.draw_arc(Vector2(bx, by), brr, 0, TAU, 10, Color(1, 1, 1, 0.42), 1.0, false)
			ci.draw_circle(Vector2(bx - brr * 0.35, by - brr * 0.35), brr * 0.28, Color(1, 1, 1, 0.50))
		else:
			# Pop! — a quick expanding ring that fades out
			var pk := (bk - 0.86) / 0.14
			ci.draw_arc(Vector2(bx, by), brr * (1.0 + pk * 0.9), 0, TAU, 10,
				Color(1, 1, 1, 0.42 * (1.0 - pk)), 1.0, false)

# ── 15 STORM (animated: thundercloud with rain + lightning strikes) ───────────
static func _storm(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	var st := col.lerp(Color(0.45, 0.50, 0.62), 0.60)
	var t := Time.get_ticks_msec() * 0.001
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.32))
	rr_grad(ci, r, rad, st.lightened(0.15), st.darkened(0.40))
	# Cloud bumps along the top
	var cloud := st.lightened(0.35)
	ci.draw_circle(r.position + r.size * Vector2(0.25, 0.18), s * 0.14, cloud)
	ci.draw_circle(r.position + r.size * Vector2(0.50, 0.14), s * 0.17, cloud)
	ci.draw_circle(r.position + r.size * Vector2(0.75, 0.19), s * 0.13, cloud)
	# Rain streaks, falling on a loop
	var rain := Color(0.75, 0.85, 1.0, 0.45)
	for i in 3:
		var rx := r.position.x + r.size.x * (0.22 + 0.28 * float(i))
		var ry := r.position.y + r.size.y * 0.42 + fmod(t * s * 0.9 + float(seed_v * 7 + i * 31) * 3.0, r.size.y * 0.45)
		ci.draw_line(Vector2(rx, ry), Vector2(rx - s * 0.03, ry + s * 0.10), rain, 1.3)
	# Lightning strike — brief, seeded phase
	var lk := fmod(t * 0.45 + float(seed_v % 11) * 0.10, 1.0)
	if lk < 0.10:
		var flash := 1.0 - lk / 0.10
		var lx := r.position.x + r.size.x * (0.35 + 0.30 * float(seed_v % 3) / 2.0)
		ci.draw_polyline(PackedVector2Array([
			Vector2(lx, r.position.y + r.size.y * 0.28),
			Vector2(lx - s * 0.07, r.position.y + r.size.y * 0.52),
			Vector2(lx + s * 0.03, r.position.y + r.size.y * 0.58),
			Vector2(lx - s * 0.05, r.position.y + r.size.y * 0.85)]),
			Color(1.0, 1.0, 0.75, 0.95 * flash), 2.0)
		rr_fill(ci, r, rad, Color(1, 1, 1, 0.14 * flash))
	rr_outline(ci, r, rad, st.lightened(0.25), 1.5)

# ── 16 SAKURA (animated: one continuous petalfall flowing across all blocks) ─
# Petals live in ABSOLUTE canvas space (vertical lanes + global fall phase),
# so every block draws its slice of the same petal field — petals drift
# seamlessly from each block into the one below it.
static func _sakura(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, _seed_v: int, pr: Rect2 = Rect2()) -> void:
	var ps := pr.size.x if pr.size.x > 0.0 else s
	var sk := col.lerp(Color(1.00, 0.75, 0.82), 0.50)
	var t := Time.get_ticks_msec() * 0.001
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.25))
	rr_grad(ci, r, rad, sk.lightened(0.32), sk.darkened(0.12))
	# Petal lanes: fixed x positions in canvas space, petals repeat vertically
	# and fall on a global clock
	# Petals are drawn slightly past the block edges (margin = petal size) and
	# in OPAQUE colours: a boundary-crossing petal gets drawn identically by
	# both neighbouring blocks, so there is no visible seam or pop-in.
	var margin := ps * 0.07
	var spacing := ps * 0.34
	var delta := r.position - pr.position
	if delta.length() < s * 0.5:
		delta = Vector2.ZERO
	var lane0 := int(floor((pr.position.x - margin) / spacing))
	var lane_count := int(ceil((pr.size.x + margin * 2.0) / spacing)) + 1
	for li in lane_count:
		var lane := lane0 + li
		var lx := float(lane) * spacing + spacing * 0.5
		if lx < pr.position.x - margin or lx > pr.end.x + margin:
			continue
		var lseed := absi(lane * 7919)
		var speed := ps * (0.40 + float(lseed % 5) * 0.07)
		var period := ps * (1.05 + float(lseed % 3) * 0.45)
		var base_y := fmod(t * speed + float(lseed % 100) * 3.7, period)
		var k0 := int(floor((pr.position.y - margin - base_y) / period))
		for k in range(k0, k0 + int(ceil((pr.size.y + margin * 2.0) / period)) + 2):
			var py := base_y + float(k) * period
			if py < pr.position.y - margin or py > pr.end.y + margin:
				continue
			var sway := sin(t * 1.8 + float(lane) * 1.3 + float(k) * 0.7) * ps * 0.05
			var p := Vector2(lx + sway, py) + delta
			var ang := t * 1.6 + float(lane * 3 + k) * 1.1
			var shade := 0.84 + 0.10 * sin(float(lane + k) * 2.3)
			_petal(ci, p, ang, ps * 0.058, Color(1.0, shade, 0.93), r)
	rr_outline(ci, r, rad, sk.darkened(0.25), 1.5)

# A cherry-blossom petal: teardrop with the classic notched tip, manually
# rotated, CLIPPED to the block rect — adjacent blocks each draw their exact
# half of a boundary-crossing petal, so it's seamless with zero overhang
static func _petal(ci: CanvasItem, p: Vector2, ang: float, size_f: float, col: Color, clip: Rect2) -> void:
	var ca := cos(ang)
	var sa := sin(ang)
	var shape := [
		Vector2(0.00, -0.62),   # notch dip (tip indent)
		Vector2(0.30, -0.95),   # tip lobe right
		Vector2(0.62, -0.30),
		Vector2(0.46, 0.55),
		Vector2(0.00, 0.90),    # base (stem end)
		Vector2(-0.46, 0.55),
		Vector2(-0.62, -0.30),
		Vector2(-0.30, -0.95),  # tip lobe left
	]
	var pts := PackedVector2Array()
	for v in shape:
		var sv : Vector2 = v * size_f
		pts.append(p + Vector2(sv.x * ca - sv.y * sa, sv.x * sa + sv.y * ca))
	var clipped := clip_poly_to_rect(pts, clip)
	draw_poly_safe(ci, clipped, col)
	# Soft highlight toward the base — only when it sits fully inside
	var hp := p + Vector2(-0.45 * sa, 0.45 * ca) * size_f
	if clip.grow(-size_f * 0.25).has_point(hp):
		ci.draw_circle(hp, size_f * 0.22, Color(1.0, 0.97, 0.98))

# ── 17 METALS (animated: polished precious metal/gem — the piece colour IS
# the material: yellow=gold, orange=copper, magenta=ruby, cyan=sapphire,
# green=emerald, purple=amethyst) ──────────────────────────────────────────────
static func _gold(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, _seed_v: int, pr: Rect2 = Rect2()) -> void:
	var ps := pr.size.x if pr.size.x > 0.0 else s
	# Metallize: boost saturation + value so any hue reads as polished material
	var mt := Color.from_hsv(col.h, minf(col.s * 1.15, 0.92), maxf(col.v, 0.80))
	var t := Time.get_ticks_msec() * 0.001
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.07), r.size), rad, Color(0, 0, 0, 0.35))
	# High-contrast metal body with a mirror "horizon" across the middle
	rr_grad(ci, r, rad, mt.lightened(0.55), mt.darkened(0.45))
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.05, s * 0.05), Vector2(r.size.x - s * 0.10, r.size.y * 0.42)),
		rad * 0.8, Color(1, 1, 1, 0.14))
	# Bevel: bright top catch, deep bottom shade
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.08, s * 0.05), Vector2(r.size.x - s * 0.16, s * 0.08)),
		s * 0.04, mt.lightened(0.65))
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.10, r.size.y - s * 0.12), Vector2(r.size.x - s * 0.20, s * 0.07)),
		s * 0.035, Color(mt.darkened(0.50).r, mt.darkened(0.50).g, mt.darkened(0.50).b, 0.55))
	# Specular glints
	ci.draw_circle(r.position + r.size * Vector2(0.22, 0.24), s * 0.040, Color(1, 1, 1, 0.85))
	ci.draw_circle(r.position + r.size * Vector2(0.30, 0.18), s * 0.020, Color(1, 1, 1, 0.65))
	var gp := r.position + r.size * Vector2(0.78, 0.70)
	ci.draw_line(gp + Vector2(-s * 0.05, 0), gp + Vector2(s * 0.05, 0), Color(1, 1, 1, 0.40), 1.2)
	ci.draw_line(gp + Vector2(0, -s * 0.05), gp + Vector2(0, s * 0.05), Color(1, 1, 1, 0.40), 1.2)
	# Board-wide gleam: ONE diagonal light streak travels across the whole
	# canvas every few seconds, lighting blocks in sequence as it passes.
	# Computed in absolute canvas space (like the sakura petalfall), so it is
	# perfectly continuous across neighbouring blocks — and clipped to each.
	var delta := r.position - pr.position
	if delta.length() < s * 0.5:
		delta = Vector2.ZERO
	var phase := fmod(t * 250.0, 900.0)
	var dmin := pr.position.x + 0.4 * pr.position.y - ps * 0.45
	var dmax := pr.end.x + 0.4 * pr.end.y
	var m := floorf((dmin - phase) / 900.0) + 1.0
	var S := phase + m * 900.0
	if S <= dmax:
		var inner := r.grow(-s * 0.04)
		var y_top := pr.position.y - 4.0
		var y_bot := pr.end.y + 4.0
		# Main band + thin trailing band, as diagonal strips x + 0.4y ∈ [b0, b0+bw]
		for band in [[0.0, ps * 0.16, 0.45], [ps * 0.24, ps * 0.07, 0.20]]:
			var b0 : float = S + band[0]
			var bw : float = band[1]
			var poly := clip_poly_to_rect(PackedVector2Array([
				Vector2(b0 - 0.4 * y_top, y_top) + delta,
				Vector2(b0 + bw - 0.4 * y_top, y_top) + delta,
				Vector2(b0 + bw - 0.4 * y_bot, y_bot) + delta,
				Vector2(b0 - 0.4 * y_bot, y_bot) + delta]), inner)
			draw_poly_safe(ci, poly, Color(1, 1, 1, float(band[2])))
	rr_outline(ci, r, rad, mt.lightened(0.35), 1.5)

# ── 18 SLIME (animated: wobbling goo) ─────────────────────────────────────────
static func _slime(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	var gl := col.lerp(Color(0.40, 0.90, 0.25), 0.55)
	var t := Time.get_ticks_msec() * 0.001
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.07), r.size), rad + s * 0.05, Color(0, 0, 0, 0.28))
	rr_grad(ci, r, rad + s * 0.05, gl.lightened(0.25), gl.darkened(0.22))
	# Bubbles rising through the goo
	for i in 2:
		var bk := fmod(t * (0.18 + float(i) * 0.07) + float(seed_v % 8 + i * 3) * 0.16, 1.0)
		var bx := r.position.x + r.size.x * (0.30 + 0.40 * float((seed_v + i * 7) % 3) / 2.0)
		ci.draw_arc(Vector2(bx, lerpf(r.end.y - s * 0.12, r.position.y + s * 0.30, bk)),
			s * (0.030 + float(i) * 0.014), 0, TAU, 10,
			Color(gl.lightened(0.55).r, gl.lightened(0.55).g, gl.lightened(0.55).b, 0.55 * (1.0 - bk * 0.5)), 1.2, false)
	# Gloss
	ci.draw_circle(r.position + r.size * Vector2(0.28, 0.42), s * 0.055, Color(1, 1, 1, 0.40))
	rr_outline(ci, r, rad + s * 0.05, gl.darkened(0.30), 1.5)

# ── 19 DISCO (animated: mirror-ball facets cycling colour) ────────────────────
static func _disco(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	var t := Time.get_ticks_msec() * 0.001
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.35))
	rr_fill(ci, r, rad, col.darkened(0.45))
	# 3x3 mirror facets, each cycling hue on its own offset
	var fs := (r.size.x - s * 0.14) / 3.0
	for fy in 3:
		for fx in 3:
			var hue := fmod(col.h + float(fx + fy) * 0.07 + t * 0.12 + float(seed_v % 9) * 0.03, 1.0)
			var bright := 0.55 + 0.40 * absf(sin(t * 1.8 + float(fx * 3 + fy) * 1.3 + float(seed_v)))
			var facet := Rect2(r.position + Vector2(s * 0.07 + float(fx) * fs, s * 0.07 + float(fy) * fs),
				Vector2(fs - s * 0.02, fs - s * 0.02))
			ci.draw_rect(facet, Color.from_hsv(hue, 0.45, bright), true)
	rr_outline(ci, r, rad, col.lightened(0.40), 1.5)

# ── 20 CAT (secret: cartoony/anime kitty face, blinks + ear-twitch) ──────────
const CAT_COATS : Array = [
	Color(0.96, 0.64, 0.32),   # ginger
	Color(0.66, 0.66, 0.70),   # grey
	Color(0.97, 0.91, 0.79),   # cream
	Color(0.58, 0.42, 0.30),   # brown
	Color(0.97, 0.96, 0.95),   # white
	Color(0.34, 0.32, 0.38),   # charcoal
]
const CAT_EYES : Array = [
	Color(0.45, 0.88, 0.50),   # green
	Color(0.40, 0.72, 1.00),   # blue
	Color(1.00, 0.76, 0.28),   # amber
	Color(0.82, 0.95, 0.38),   # yellow-green
]

static func _cat(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	var sv := absi(seed_v)
	# Each cat: a coat colour (subtly tinted by the piece colour), a marking
	# pattern and an eye colour — all from the per-block seed for real variety
	var coat : Color = CAT_COATS[sv % CAT_COATS.size()]
	var fur := coat.lerp(col, 0.16)
	var dark := fur.darkened(0.45) if fur.v > 0.4 else fur.lightened(0.30)
	var pattern := (sv / CAT_COATS.size()) % 4
	var eye_col : Color = CAT_EYES[(sv / 24) % CAT_EYES.size()]
	var t := Time.get_ticks_msec() * 0.001
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.28))
	var c := r.get_center()
	# Ears (triangles up top, with pink inner) — a gentle twitch
	var tw := sin(t * 2.0 + float(seed_v)) * s * 0.012
	for sgn : float in [-1.0, 1.0]:
		var ex := c.x + sgn * s * 0.26
		var ey := r.position.y + s * 0.16
		ci.draw_polygon(PackedVector2Array([
			Vector2(ex - s * 0.14, ey + s * 0.02), Vector2(ex + sgn * tw, ey - s * 0.18),
			Vector2(ex + s * 0.14, ey + s * 0.02)]), PackedColorArray([fur.darkened(0.10)]))
		ci.draw_polygon(PackedVector2Array([
			Vector2(ex - s * 0.06, ey - s * 0.01), Vector2(ex + sgn * tw, ey - s * 0.12),
			Vector2(ex + s * 0.06, ey - s * 0.01)]), PackedColorArray([Color(1.0, 0.65, 0.72)]))
	# Head
	rr_grad(ci, r, rad, fur.lightened(0.18), fur.darkened(0.12))
	rr_outline(ci, r, rad, dark, 1.5)
	# Markings (drawn under the eyes) — gives each cat a distinct coat pattern
	match pattern:
		1:  # tabby — forehead stripes + cheek dashes
			var mc := fur.darkened(0.26) if fur.v > 0.4 else fur.lightened(0.22)
			for k : int in [-1, 0, 1]:
				var mx := c.x + float(k) * s * 0.085
				ci.draw_line(Vector2(mx, r.position.y + s * 0.30),
					Vector2(mx + float(k) * s * 0.03, r.position.y + s * 0.17), mc, 2.2)
			for sgn3 : float in [-1.0, 1.0]:
				ci.draw_line(Vector2(c.x + sgn3 * s * 0.33, c.y + s * 0.04),
					Vector2(c.x + sgn3 * s * 0.44, c.y + s * 0.09), mc, 2.0)
		2:  # patch over one eye
			var side := 1.0 if (sv % 2 == 0) else -1.0
			ci.draw_circle(Vector2(c.x + side * s * 0.20, c.y - s * 0.02), s * 0.21,
				fur.darkened(0.30) if fur.v > 0.4 else fur.lightened(0.26))
		3:  # white blaze down the face + light muzzle
			var blaze := Color(1, 1, 1, 0.55)
			ci.draw_polygon(PackedVector2Array([
				Vector2(c.x - s * 0.07, r.position.y + s * 0.16),
				Vector2(c.x + s * 0.07, r.position.y + s * 0.16),
				Vector2(c.x, c.y + s * 0.16)]), PackedColorArray([blaze]))
			ci.draw_circle(Vector2(c.x, c.y + s * 0.26), s * 0.15, blaze)
	# Eyes — big anime eyes that blink (~every few seconds, seeded phase)
	var blink := fmod(t * 0.6 + float(seed_v % 11) * 0.5, 1.0)
	var open := blink > 0.06
	var eye_y := c.y + s * 0.02
	for sgn2 : float in [-1.0, 1.0]:
		var ex2 := c.x + sgn2 * s * 0.20
		if open:
			ci.draw_circle(Vector2(ex2, eye_y), s * 0.115, Color(0.10, 0.09, 0.14))   # eye
			ci.draw_circle(Vector2(ex2, eye_y), s * 0.115, dark)
			ci.draw_circle(Vector2(ex2, eye_y + s * 0.01), s * 0.085, Color(0.12, 0.10, 0.16))
			# Iris glow + sparkle (seeded eye colour)
			ci.draw_circle(Vector2(ex2, eye_y + s * 0.015), s * 0.05,
				Color(eye_col.r, eye_col.g, eye_col.b, 0.9))
			ci.draw_circle(Vector2(ex2 - s * 0.03, eye_y - s * 0.03), s * 0.028, Color(1, 1, 1, 0.95))
			ci.draw_circle(Vector2(ex2 + s * 0.025, eye_y + s * 0.03), s * 0.014, Color(1, 1, 1, 0.6))
		else:
			# Closed: a happy upward curve  ^_^
			ci.draw_arc(Vector2(ex2, eye_y + s * 0.04), s * 0.10, PI * 1.15, PI * 1.85, 8, dark, 2.0)
	# Blush cheeks
	ci.draw_circle(c + Vector2(-s * 0.30, s * 0.10), s * 0.05, Color(1.0, 0.55, 0.65, 0.5))
	ci.draw_circle(c + Vector2(s * 0.30, s * 0.10), s * 0.05, Color(1.0, 0.55, 0.65, 0.5))
	# Nose (:3 mouth)
	var nx := c.x
	var ny := c.y + s * 0.18
	ci.draw_polygon(PackedVector2Array([
		Vector2(nx - s * 0.035, ny), Vector2(nx + s * 0.035, ny), Vector2(nx, ny + s * 0.03)]),
		PackedColorArray([Color(1.0, 0.55, 0.62)]))
	ci.draw_arc(Vector2(nx - s * 0.05, ny + s * 0.04), s * 0.05, 0, PI, 6, dark, 1.3)
	ci.draw_arc(Vector2(nx + s * 0.05, ny + s * 0.04), s * 0.05, 0, PI, 6, dark, 1.3)
	# Whiskers
	for wy in [ny - s * 0.02, ny + s * 0.05]:
		ci.draw_line(Vector2(c.x - s * 0.20, wy), Vector2(c.x - s * 0.42, wy - s * 0.03), dark, 1.2)
		ci.draw_line(Vector2(c.x + s * 0.20, wy), Vector2(c.x + s * 0.42, wy - s * 0.03), dark, 1.2)

# ── 11 GALAXY (animated) ──────────────────────────────────────────────────────
static func _galaxy(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	var g := col.lerp(Color(0.45, 0.22, 0.80), 0.55)
	var t := Time.get_ticks_msec() * 0.001
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.35))
	rr_grad(ci, r, rad, g.darkened(0.45), Color(0.06, 0.03, 0.12))
	var np := r.position + r.size * Vector2(0.35 + float(seed_v % 4) * 0.10, 0.40 + float(seed_v % 3) * 0.12)
	ci.draw_circle(np, s * 0.28, Color(g.r, g.g, g.b, 0.18))
	ci.draw_circle(np + Vector2(s * 0.11, -s * 0.09), s * 0.16,
		Color(g.lightened(0.30).r, g.lightened(0.30).g, g.lightened(0.30).b, 0.15))
	for i in 5:
		var px : float = r.position.x + s * 0.11 + float((seed_v * 31 + i * 47) % 100) / 100.0 * (r.size.x - s * 0.23)
		var py : float = r.position.y + s * 0.11 + float((seed_v * 19 + i * 61) % 100) / 100.0 * (r.size.y - s * 0.23)
		var tw : float = 0.35 + 0.65 * absf(sin(t * 2.0 + float(seed_v + i * 7) * 1.3))
		ci.draw_circle(Vector2(px, py), s * 0.03, Color(1, 1, 1, tw))
	# Hero star lands somewhere different on every block (seeded)
	var hx := 0.18 + float((seed_v * 53) % 100) / 100.0 * 0.64
	var hy := 0.15 + float((seed_v * 29) % 100) / 100.0 * 0.58
	var hp := r.position + r.size * Vector2(hx, hy)
	var ha := 0.45 + 0.55 * absf(sin(t * 1.6 + float(seed_v) * 0.9))
	ci.draw_line(hp + Vector2(-s * 0.09, 0), hp + Vector2(s * 0.09, 0), Color(1, 1, 1, ha), 1.0)
	ci.draw_line(hp + Vector2(0, -s * 0.09), hp + Vector2(0, s * 0.09), Color(1, 1, 1, ha), 1.0)
	ci.draw_circle(hp, s * 0.036, Color(1, 1, 1, ha))
	rr_outline(ci, r, rad, g.lightened(0.25), 1.5)

# ── 20 AURORA (animated: ONE continuous wavy curtain across the whole board) ─
# Night sky with twinkling stars. The aurora is a set of horizontal light bands
# living in pr (pattern) space — each band's centreline ripples on two sine
# harmonics of the ABSOLUTE x, so the curtains wave all over and flow unbroken
# from block to block. Each band is drawn as clipped halo→core ribbons.
static func _aurora(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int, pr: Rect2 = Rect2()) -> void:
	var ps := pr.size.x if pr.size.x > 0.0 else s
	var t := Time.get_ticks_msec() * 0.001
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.30))
	rr_grad(ci, r, rad, Color(0.04, 0.06, 0.18), Color(0.02, 0.10, 0.16))
	# Twinkling stars (per block — just points, no need to be continuous)
	for i in 4:
		var hsh := seed_v * 41 + i * 97
		var stx : float = r.position.x + s * (0.12 + float(hsh % 76) / 100.0)
		var sty : float = r.position.y + s * (0.08 + float((hsh / 7) % 46) / 100.0)
		var tw : float = 0.4 + 0.6 * absf(sin(t * 2.0 + float(hsh)))
		ci.draw_circle(Vector2(stx, sty), s * 0.013, Color(1, 1, 1, 0.5 * tw))
	# Continuous aurora curtains
	var delta := r.position - pr.position
	if delta.length() < s * 0.5:
		delta = Vector2.ZERO
	var band_spacing := ps * 1.4
	var nx := 6
	var passes := [[0.55, 0.10, 0.0], [0.30, 0.15, 0.0], [0.10, 0.34, 0.35]]   # [thick, alpha, lighten]
	var b0 := int(floor((pr.position.y - band_spacing * 1.5) / band_spacing))
	var b1 := int(ceil((pr.end.y + band_spacing * 1.5) / band_spacing))
	for band in range(b0, b1 + 1):
		var by : float = float(band) * band_spacing
		var bphase : float = float(absi(band * 2654435) % 1000) / 1000.0 * TAU
		var hue : float = fmod(0.30 + col.h * 0.35 + float(band) * 0.13 + 0.05 * sin(t * 0.3 + bphase), 1.0)
		var ac := Color.from_hsv(hue, 0.62, 1.0)
		# Centreline y for a given absolute x — two harmonics so it ripples all over
		var cx0 := pr.position.x
		var cx1 := pr.end.x
		var ys := PackedFloat32Array()
		var xs := PackedFloat32Array()
		for k in nx + 1:
			var px : float = lerpf(cx0, cx1, float(k) / float(nx))
			xs.append(px)
			ys.append(by + sin(px * (2.4 / ps) + t * 0.5 + bphase) * ps * 0.45
				+ sin(px * (5.1 / ps) - t * 0.35 + bphase * 1.7) * ps * 0.20)
		for p : Array in passes:
			var thick : float = ps * float(p[0]) * (0.8 + 0.4 * sin(bphase))
			var pc := ac.lerp(Color(1, 1, 1, 1), float(p[2]))
			var top := PackedVector2Array()
			var bot := PackedVector2Array()
			for k in nx + 1:
				top.append(Vector2(xs[k], ys[k] - thick * 0.5) + delta)
				bot.append(Vector2(xs[k], ys[k] + thick * 0.5) + delta)
			var poly := top.duplicate()
			for k in range(bot.size() - 1, -1, -1):
				poly.append(bot[k])
			draw_poly_safe(ci, clip_poly_to_rect(poly, r), Color(pc.r, pc.g, pc.b, float(p[1])))
	rr_outline(ci, r, rad, Color(0.30, 0.50, 0.60, 0.5), 1.5)

# ── 21 PLASMA (animated: electric energy ball) ───────────────────────────────
# Dark glass with a pulsing glowing core and jagged electric arcs crackling out
# toward the edges; the energy colour is the piece colour pushed toward violet.
static func _plasma(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var pc := col.lerp(Color(0.45, 0.35, 1.00), 0.50)   # electric blue-violet, piece-tinted
	var pulse := 0.5 + 0.5 * sin(t * 4.0 + float(seed_v % 9))
	var c := r.get_center()
	# Dark glass sphere
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.40))
	rr_grad(ci, r, rad, Color(0.09, 0.05, 0.20), Color(0.03, 0.02, 0.09))
	# Soft energy haze filling the globe
	ci.draw_circle(c, s * 0.42, Color(pc.r, pc.g, pc.b, 0.07 + 0.05 * pulse))
	# Lightning tendrils — each snakes from the core out to a wandering anchor on
	# the glass shell, drawn as a coloured halo with a white-hot core line, and a
	# bright spark where it kisses the glass.
	var h := seed_v
	var arms := 5
	for arm in arms:
		h = (h * 1103515 + 12345) % 2147483647
		var ang : float = float(arm) * TAU / float(arms) + t * 0.5 + 0.4 * sin(t * 1.3 + float(arm))
		var reach : float = s * (0.34 + 0.06 * sin(t * 5.0 + float(arm) * 2.0 + float(h % 7)))
		var pts := PackedVector2Array([c])
		var steps := 5
		for k in range(1, steps + 1):
			var f : float = float(k) / float(steps)
			var perp : float = ang + PI * 0.5
			var jit : float = sin(t * 11.0 + float(arm) * 3.0 + float(k) * 2.3 + float(h % 11)) * s * 0.055 * (1.0 - f * 0.5)
			pts.append(c + Vector2(cos(ang), sin(ang)) * (f * reach) + Vector2(cos(perp), sin(perp)) * jit)
		var tip := pts[pts.size() - 1]
		ci.draw_polyline(pts, Color(pc.lightened(0.30).r, pc.lightened(0.30).g, pc.lightened(0.30).b, 0.35 + 0.25 * pulse), 3.0)
		ci.draw_polyline(pts, Color(1, 1, 1, 0.70), 1.2)
		ci.draw_circle(tip, s * 0.022, Color(pc.lightened(0.60).r, pc.lightened(0.60).g, pc.lightened(0.60).b, 0.70))
	# Hot core on top of the tendril roots
	ci.draw_circle(c, s * (0.15 + 0.04 * pulse),
		Color(pc.lightened(0.45).r, pc.lightened(0.45).g, pc.lightened(0.45).b, 0.35 + 0.25 * pulse))
	ci.draw_circle(c, s * 0.075, Color(1, 1, 1, 0.70 + 0.25 * pulse))
	# Glass shell highlight (top-left crescent) + rim
	ci.draw_arc(c, s * 0.40, PI * 0.95, PI * 1.50, 12, Color(1, 1, 1, 0.20), 2.0, false)
	rr_outline(ci, r, rad, pc.lightened(0.35), 1.5)

# ── 22 MARBLE (veined stone — veins line up continuously across the board) ───
# Luxe stone tile: piece colour washed near-white with darker jagged veins. The
# veins live in pr (pattern) space as value-noise lanes, so each block draws the
# slice crossing it and the cracks run unbroken across neighbouring blocks.
# Same canvas-continuous trick as honey/sakura/metals; static.
static func _marble(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int, pr: Rect2 = Rect2()) -> void:
	var ps := pr.size.x if pr.size.x > 0.0 else s
	var base := col.lerp(Color(0.95, 0.95, 0.93), 0.78)
	var vein := col.lerp(Color(0.32, 0.30, 0.38), 0.62)
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.25))
	rr_grad(ci, r, rad, base.lightened(0.12), base.darkened(0.08))
	# Pattern-space translation (zeroed for tiny squash wobble), so the vein field
	# stays put while a cell animates and matches across blocks + drag preview.
	var delta := r.position - pr.position
	if delta.length() < s * 0.5:
		delta = Vector2.ZERO
	var spacing := ps * 0.62      # horizontal gap between vein lanes
	var seg := ps * 0.30          # vertical spacing of value-noise nodes
	var scan := spacing * 1.6
	var lane0 := int(floor((pr.position.x - scan) / spacing))
	var lane1 := int(ceil((pr.end.x + scan) / spacing))
	var j0 := int(floor((pr.position.y - seg) / seg)) - 1
	var j1 := int(ceil((pr.end.y + seg) / seg)) + 1
	# Each vein flows on a low-frequency diagonal SWEEP (so it crosses the board
	# instead of sitting in a vertical lane) plus fine value-noise jitter, and its
	# WIDTH tapers along the run. Drawn as 3 ribbons — wide soft halo, mid, thin
	# dark core — each clipped to the block so neighbours fill matching slices and
	# the cracks stay unbroken across the whole board.
	var passes := [[0.13, 0.07], [0.075, 0.14], [0.03, 0.44]]
	for p : Array in passes:
		var pw : float = s * float(p[0])
		var vc := Color(vein.r, vein.g, vein.b, float(p[1]))
		for lane in range(lane0, lane1 + 1):
			var lane_base : float = float(lane) * spacing
			var lphase : float = float(absi(lane * 2654435) % 1000) / 1000.0 * TAU
			var left := PackedVector2Array()
			var right := PackedVector2Array()
			for j in range(j0, j1 + 1):
				var y : float = float(j) * seg
				var hsh := absi((lane * 73856093) ^ (j * 19349663))
				var jit : float = (float(hsh % 1000) / 1000.0 - 0.5) * spacing * 0.5
				var sweep : float = sin(y / (ps * 3.2) * PI + lphase) * spacing * 0.6
				var x : float = lane_base + sweep + jit
				var wv : float = pw * (0.55 + 0.9 * float((hsh / 7) % 100) / 100.0)
				left.append(Vector2(x - wv * 0.5, y) + delta)
				right.append(Vector2(x + wv * 0.5, y) + delta)
			var poly := left.duplicate()
			for k in range(right.size() - 1, -1, -1):
				poly.append(right[k])
			draw_poly_safe(ci, clip_poly_to_rect(poly, r), vc)
	# Mineral flecks for a stony read (per block, stable from the cell seed)
	for i in 4:
		var fx : float = r.position.x + s * (0.12 + float((seed_v * 13 + i * 29) % 76) / 100.0)
		var fyy : float = r.position.y + s * (0.12 + float((seed_v * 7 + i * 53) % 76) / 100.0)
		ci.draw_circle(Vector2(fx, fyy), s * 0.010, Color(vein.r, vein.g, vein.b, 0.16))
	# Soft diagonal sheen + a glossy corner highlight (per block — it's lighting)
	var sheen := clip_poly_to_rect(PackedVector2Array([
		r.position + Vector2(s * 0.10, 0), r.position + Vector2(s * 0.34, 0),
		r.position + Vector2(-s * 0.06, r.size.y), r.position + Vector2(-s * 0.30, r.size.y)]), r)
	draw_poly_safe(ci, sheen, Color(1, 1, 1, 0.12))
	ci.draw_circle(r.position + r.size * Vector2(0.28, 0.26), s * 0.05, Color(1, 1, 1, 0.20))
	rr_outline(ci, r, rad, base.darkened(0.22), 1.5)

# ── 23 MATRIX (animated: falling digital code rain) ──────────────────────────
# Black-green screen with columns of glyph pixels streaming down; the lead glyph
# of each column glows white, the trail fades. Piece colour tints the green.
static func _matrix(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var g := col.lerp(Color(0.20, 1.00, 0.35), 0.70)
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.40))
	rr_grad(ci, r, rad, Color(0.02, 0.10, 0.04), Color(0.01, 0.04, 0.02))
	var cols := 3
	var cw := r.size.x / float(cols)
	var cell := s * 0.13
	for cidx in cols:
		var cx : float = r.position.x + (float(cidx) + 0.5) * cw
		var spd : float = 0.55 + 0.18 * float((seed_v * 7 + cidx * 13) % 5)
		var head : float = fmod(t * spd + float((seed_v * 3 + cidx * 29) % 10) * 0.3, 1.4) * r.size.y
		for k in 5:
			var gy : float = r.position.y + head - float(k) * cell * 1.15
			if gy < r.position.y + s * 0.05 or gy > r.end.y - s * 0.05:
				continue
			var a : float = 1.0 - float(k) / 5.0
			var gc : Color = Color(1, 1, 1, a) if k == 0 else Color(g.r, g.g, g.b, a * 0.8)
			ci.draw_rect(Rect2(cx - cell * 0.4, gy - cell * 0.4, cell * 0.8, cell * 0.8), gc, true)
	rr_outline(ci, r, rad, g.darkened(0.20), 1.5)

# ── 24 HOLOGRAM (animated: iridescent foil) ──────────────────────────────────
# Holographic trading-card foil: a hue-shifting gradient, rolling scanlines and
# a diagonal glint that sweeps across the block.
static func _hologram(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var hue : float = fmod(col.h + 0.18 * sin(t * 0.8 + float(seed_v % 11) * 0.6), 1.0)
	if hue < 0.0:
		hue += 1.0
	var top := Color.from_hsv(hue, 0.55, 1.0)
	var bot := Color.from_hsv(fmod(hue + 0.35, 1.0), 0.60, 0.90)
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.30))
	rr_grad(ci, r, rad, top.lerp(Color(0.10, 0.10, 0.15), 0.35), bot.lerp(Color(0.05, 0.05, 0.10), 0.45))
	# Rolling horizontal scanlines
	var step := s * 0.13
	var y : float = r.position.y + fmod(t * s * 0.25, step)
	while y < r.end.y:
		ci.draw_line(Vector2(r.position.x + s * 0.06, y), Vector2(r.end.x - s * 0.06, y), Color(1, 1, 1, 0.10), 1.0)
		y += step
	# Diagonal glint sweeping across, clipped to the block
	var sweep := fmod(t * 0.5, 1.0)
	var gx : float = lerpf(r.position.x - s * 0.40, r.end.x + s * 0.40, sweep)
	var gw := s * 0.22
	var glint := clip_poly_to_rect(PackedVector2Array([
		Vector2(gx, r.position.y), Vector2(gx + gw, r.position.y),
		Vector2(gx + gw - s * 0.30, r.end.y), Vector2(gx - s * 0.30, r.end.y)]), r)
	draw_poly_safe(ci, glint, Color(1, 1, 1, 0.16))
	rr_outline(ci, r, rad, top.lightened(0.30), 1.6)

# ── 25 PRISM (animated: clear glass refracting a rainbow that flows the board) ─
# The spectrum hue is a function of CANVAS position + time, so one continuous
# rainbow sweeps diagonally across every block. A caustic gleam travels too.
static func _prism(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, _seed_v: int, pr: Rect2 = Rect2()) -> void:
	var ps := pr.size.x if pr.size.x > 0.0 else s
	var t := Time.get_ticks_msec() * 0.001
	var ctr := pr.get_center()
	var hue : float = fmod((ctr.x + ctr.y) / (ps * 7.0) + t * 0.07, 1.0)
	if hue < 0.0:
		hue += 1.0
	var spec := Color.from_hsv(hue, 0.80, 1.0)
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.25))
	var base := col.lerp(spec, 0.60)
	rr_grad(ci, r, rad, base.lightened(0.40), base.darkened(0.08))
	# Lower-half refracted secondary hue (light splitting)
	var spec2 := Color.from_hsv(fmod(hue + 0.5, 1.0), 0.70, 1.0)
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.07, r.size.y * 0.56), Vector2(r.size.x - s * 0.14, r.size.y * 0.40)),
		rad * 0.5, Color(spec2.r, spec2.g, spec2.b, 0.18))
	# Moving caustic gleam — absolute-canvas diagonal strip, continuous + clipped
	var delta := r.position - pr.position
	if delta.length() < s * 0.5:
		delta = Vector2.ZERO
	var phase := fmod(t * 200.0, 760.0)
	var dmin := pr.position.x + 0.5 * pr.position.y - ps * 0.5
	var dmax := pr.end.x + 0.5 * pr.end.y
	var m := floorf((dmin - phase) / 760.0) + 1.0
	var S := phase + m * 760.0
	if S <= dmax:
		var y_top := pr.position.y - 4.0
		var y_bot := pr.end.y + 4.0
		var bw := ps * 0.22
		draw_poly_safe(ci, clip_poly_to_rect(PackedVector2Array([
			Vector2(S - 0.5 * y_top, y_top) + delta,
			Vector2(S + bw - 0.5 * y_top, y_top) + delta,
			Vector2(S + bw - 0.5 * y_bot, y_bot) + delta,
			Vector2(S - 0.5 * y_bot, y_bot) + delta]), r), Color(1, 1, 1, 0.35))
	# Crisp glass facet (top-left bright triangle) + sparkle
	draw_poly_safe(ci, PackedVector2Array([
		r.position + Vector2(s * 0.12, s * 0.12),
		r.position + Vector2(s * 0.52, s * 0.14),
		r.position + Vector2(s * 0.16, s * 0.52)]), Color(1, 1, 1, 0.16))
	ci.draw_circle(r.position + r.size * Vector2(0.72, 0.30), s * 0.03, Color(1, 1, 1, 0.75))
	rr_outline(ci, r, rad, Color(1, 1, 1, 0.45), 1.5)

# ── 26 STAINED (animated: one continuous leaded diamond window across the board) ─
# Jewel diamonds tiled in pr (pattern) space with dark lead came between them, so
# neighbouring blocks form a single cathedral window. A band of sunlight drifts
# diagonally across, brightening the glass it passes. Each diamond a varied hue.
static func _stained(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, _seed_v: int, pr: Rect2 = Rect2()) -> void:
	var ps := pr.size.x if pr.size.x > 0.0 else s
	var t := Time.get_ticks_msec() * 0.001
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.30))
	rr_fill(ci, r, rad, Color(0.05, 0.04, 0.07))   # dark lead came shows in the gaps
	var inner := r.grow(-s * 0.04)
	var delta := r.position - pr.position
	if delta.length() < s * 0.5:
		delta = Vector2.ZERO
	# Diamonds sit on grid points where (i+j) is even — that set tiles the plane.
	var g := ps * 0.38           # diamond half-diagonal
	var gg := g - ps * 0.045     # inset for the lead gap
	var i0 := int(floor(pr.position.x / g)) - 1
	var i1 := int(ceil(pr.end.x / g)) + 1
	var j0 := int(floor(pr.position.y / g)) - 1
	var j1 := int(ceil(pr.end.y / g)) + 1
	for i in range(i0, i1 + 1):
		for j in range(j0, j1 + 1):
			if (i + j) % 2 != 0:
				continue
			var cx : float = float(i) * g + delta.x
			var cy : float = float(j) * g + delta.y
			var dia := PackedVector2Array([
				Vector2(cx, cy - gg), Vector2(cx + gg, cy),
				Vector2(cx, cy + gg), Vector2(cx - gg, cy)])
			var clipped := clip_poly_to_rect(dia, inner)
			if clipped.size() < 3:
				continue
			var hsh := absi((i * 73856093) ^ (j * 19349663))
			var jhue : float = fmod(col.h + float(hsh % 1000) / 1000.0, 1.0)
			var wave : float = 0.5 + 0.5 * sin((cx + cy) / (ps * 2.6) - t * 0.7)
			# Backlit glass: bright light behind, then the colour as a TRANSLUCENT
			# layer over it. Where the light sweeps, the glass goes more transparent
			# (paler/brighter) — like sun shining through from the far side.
			draw_poly_safe(ci, clipped, Color(1.0, 0.98, 0.92), true)
			var jewel := Color.from_hsv(jhue, 0.90, 1.0)
			var ja : float = 0.50 + 0.24 * (1.0 - wave)
			draw_poly_safe(ci, clipped, Color(jewel.r, jewel.g, jewel.b, ja), true)
			# Glint where the light passes through the thin centre of the pane —
			# only when the diamond's centre is inside this block (no stray orbs)
			if inner.has_point(Vector2(cx, cy)):
				ci.draw_circle(Vector2(cx, cy), gg * 0.22, Color(1, 1, 1, 0.10 + 0.22 * wave))
			# Glass bevel — only on diamonds fully inside the block so the came
			# lines never spill into the gaps between blocks
			var v_top := Vector2(cx, cy - gg)
			var v_left := Vector2(cx - gg, cy)
			var v_right := Vector2(cx + gg, cy)
			var v_bot := Vector2(cx, cy + gg)
			if inner.has_point(v_top) and inner.has_point(v_left):
				ci.draw_line(v_top, v_left, jewel.lightened(0.45), 1.0)
			if inner.has_point(v_right) and inner.has_point(v_bot):
				ci.draw_line(v_right, v_bot, jewel.darkened(0.25), 1.0)
	rr_outline(ci, r, rad, Color(0.02, 0.02, 0.03, 0.95), 2.0)

# ── 27 SYNTHWAVE (animated: a self-contained 80s neon CRT tile) ──────────────
# Sunset gradient, a glowing horizon, CRT scanlines + a sweep that ride INSIDE
# the block, and a magenta/cyan neon double-edge. Everything stays in bounds.
static func _synthwave(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, _seed_v: int) -> void:
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.30))
	var top := col.lerp(Color(1.0, 0.18, 0.62), 0.60)   # hot magenta
	var bot := col.lerp(Color(0.22, 0.55, 1.0), 0.55)   # cyan
	rr_grad(ci, r, rad, top, bot)
	# Glowing sunset horizon across the middle
	var hy := r.position.y + r.size.y * 0.5
	rr_fill(ci, Rect2(r.position.x + s * 0.06, hy - s * 0.05, r.size.x - s * 0.12, s * 0.10),
		s * 0.04, Color(1.0, 0.82, 0.42, 0.38))
	# CRT scanlines, brighter toward the horizon (all within the block)
	var n := 6
	for i in n:
		var fy : float = float(i) / float(n - 1)
		var ly : float = r.position.y + s * 0.12 + fy * (r.size.y - s * 0.24)
		var a : float = 0.10 + 0.12 * (1.0 - absf(fy - 0.5) * 2.0)
		ci.draw_line(Vector2(r.position.x + s * 0.08, ly), Vector2(r.end.x - s * 0.08, ly),
			Color(0.6, 1.0, 0.95, a), 1.0)
	# Chrome top catch + neon double edge (magenta outer, cyan inner)
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.08, s * 0.06), Vector2(r.size.x - s * 0.16, s * 0.06)),
		s * 0.03, Color(1, 1, 1, 0.18))
	rr_outline(ci, r, rad, Color(1.0, 0.4, 0.85, 0.7), 2.0)
	rr_outline(ci, r.grow(-s * 0.045), rad * 0.8, Color(0.45, 1.0, 0.95, 0.35), 1.0)

# ── 28 AUTUMN (animated: warm wood with a continuous fall of tumbling leaves) ─
static func _autumn(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, _seed_v: int, pr: Rect2 = Rect2()) -> void:
	var ps := pr.size.x if pr.size.x > 0.0 else s
	var t := Time.get_ticks_msec() * 0.001
	var base := col.lerp(Color(0.55, 0.32, 0.14), 0.62)
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.28))
	rr_grad(ci, r, rad, base.lightened(0.28), base.darkened(0.14))
	var leaf_cols : Array = [Color(0.85, 0.22, 0.10), Color(0.95, 0.48, 0.10),
		Color(0.93, 0.74, 0.20), Color(0.70, 0.34, 0.12)]
	var margin := ps * 0.08
	var spacing := ps * 0.40
	var delta := r.position - pr.position
	if delta.length() < s * 0.5:
		delta = Vector2.ZERO
	var lane0 := int(floor((pr.position.x - margin) / spacing))
	var lane_count := int(ceil((pr.size.x + margin * 2.0) / spacing)) + 1
	for li in lane_count:
		var lane := lane0 + li
		var lx := float(lane) * spacing + spacing * 0.5
		if lx < pr.position.x - margin or lx > pr.end.x + margin:
			continue
		var lseed := absi(lane * 7919)
		var speed := ps * (0.30 + float(lseed % 5) * 0.06)
		var period := ps * (1.1 + float(lseed % 3) * 0.5)
		var base_y := fmod(t * speed + float(lseed % 100) * 3.7, period)
		var k0 := int(floor((pr.position.y - margin - base_y) / period))
		for k in range(k0, k0 + int(ceil((pr.size.y + margin * 2.0) / period)) + 2):
			var py := base_y + float(k) * period
			if py < pr.position.y - margin or py > pr.end.y + margin:
				continue
			var sway := sin(t * 1.4 + float(lane) * 1.3 + float(k) * 0.6) * ps * 0.07
			var p := Vector2(lx + sway, py) + delta
			var ang := t * 2.2 + float(lane * 3 + k) * 1.1
			var lc : Color = leaf_cols[absi(lane * 3 + k) % leaf_cols.size()]
			_leaf(ci, p, ang, ps * 0.075, lc, r)
	rr_outline(ci, r, rad, base.darkened(0.30), 1.5)

# A simple pointed leaf with a centre vein, manually rotated + clipped per block
static func _leaf(ci: CanvasItem, p: Vector2, ang: float, size_f: float, col: Color, clip: Rect2) -> void:
	var ca := cos(ang)
	var sa := sin(ang)
	var shape := [Vector2(0.0, -0.95), Vector2(0.42, -0.30), Vector2(0.30, 0.42),
		Vector2(0.0, 0.85), Vector2(-0.30, 0.42), Vector2(-0.42, -0.30)]
	var pts := PackedVector2Array()
	for v in shape:
		var sv : Vector2 = v * size_f
		pts.append(p + Vector2(sv.x * ca - sv.y * sa, sv.x * sa + sv.y * ca))
	draw_poly_safe(ci, clip_poly_to_rect(pts, clip), col)
	if clip.has_point(p):
		var tip := p + Vector2((-(-0.95) * sa), ((-0.95) * ca)) * size_f
		var basep := p + Vector2((-(0.85) * sa), ((0.85) * ca)) * size_f
		ci.draw_line(basep, tip, Color(col.darkened(0.35).r, col.darkened(0.35).g, col.darkened(0.35).b, 0.6), 1.0)

# ── 29 WARP (animated: a swirling wormhole vortex, self-contained) ───────────
# Deep-space block with rotating spiral arms, rings rushing outward and a bright
# pulsing core — a hyperspace portal. Everything stays within the block radius.
static func _warp(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var ph0 := float(seed_v) * 0.6   # per-block phase so blocks aren't identical
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.30))
	var deep := col.lerp(Color(0.05, 0.03, 0.17), 0.80)
	rr_grad(ci, r, rad, deep.lightened(0.05), Color(0.02, 0.02, 0.08))
	var c := r.get_center()
	var maxr := s * 0.44
	# Outer energy haze
	ci.draw_circle(c, maxr, Color(0.30, 0.42, 0.95, 0.06))
	# Rings rushing outward (the tunnel)
	for i in 3:
		var rp : float = fmod(t * 0.5 + ph0 + float(i) / 3.0, 1.0)
		ci.draw_arc(c, rp * maxr, 0, TAU, 28, Color(0.55, 0.80, 1.0, (1.0 - rp) * 0.40), 1.5, true)
	# Spiral arms swirling inward, brighter + fatter toward the core
	var arms := 2
	var steps := 14
	for arm in arms:
		var a0 := t * 1.5 + ph0 + float(arm) / float(arms) * TAU
		var prev := c
		for i in steps + 1:
			var f : float = float(i) / float(steps)
			var ang : float = a0 + f * 4.6   # twist
			var p := c + Vector2(cos(ang), sin(ang)) * (f * maxr)
			if i > 0:
				var a : float = lerpf(0.75, 0.05, f)
				var hue := fmod(0.58 + f * 0.18 + ph0 * 0.05, 1.0)
				ci.draw_line(prev, p, Color.from_hsv(hue, 0.45, 1.0, a), lerpf(2.6, 0.8, f))
			prev = p
	# Bright pulsing core with a white-hot centre
	var pulse := 0.5 + 0.5 * sin(t * 3.0 + ph0)
	ci.draw_circle(c, s * (0.07 + 0.025 * pulse), Color(0.70, 0.90, 1.0, 0.40 + 0.30 * pulse))
	ci.draw_circle(c, s * 0.035, Color(1, 1, 1, 0.85 + 0.15 * pulse))
	rr_outline(ci, r, rad, Color(0.40, 0.50, 0.90, 0.40), 1.5)
