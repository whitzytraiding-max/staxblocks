extends CanvasLayer

# ── First-run tutorial coach ─────────────────────────────────────────────────
# One clean, continuous lesson that flows straight into the player's real run —
# no board resets, no jarring scene swaps. "Cubie" walks them through it:
#   1. Place three guided blocks (locked to exact spots) → a TRIPLE clear.
#   2. Place the next set freely.
#   3. Earn a Power Orb, fire the bomb, get the good-luck send-off.
# When it ends the coach simply vanishes and the same game keeps going.
#
# Driven by events Game.gd forwards (on_event) + tap-to-continue on gated steps.

enum { S_WELCOME, S_PLACE1, S_PLACE2, S_PLACE3, S_FREE, S_BOMB, S_GOODLUCK, S_FINISHED }

const SCREEN := Vector2(414.0, 896.0)

# Board geometry mirrored from Game.gd so spotlights line up exactly
const GRID_X    := 24.0
const GRID_Y    := 175.0
const CELL      := 44.0
const GRID_STEP := 46.0

# Scripted-board palette
const C_ROW := Color(0.32, 0.80, 0.97)

# Power orb hit area (mirrors Game POWER_CENTER 50,70 / POWER_R 30)
const POWER_RECT := Rect2(14.0, 34.0, 72.0, 72.0)

# The three guided placements: a vertical bar dropped into each open column of
# the bottom-right gap. The third one completes rows 5, 6 and 7 at once.
const GUIDE := [
	{"slot": 0, "col": 5},
	{"slot": 1, "col": 6},
	{"slot": 2, "col": 7},
]
const BAR := [[0, 0], [0, 1], [0, 2]]
const FREE_TARGET := 3   # place a full set freely before the bomb lesson
const TEXT_W := 250.0    # bubble text column width (fixes autowrap)

var game : Node2D = null
var grid : Node   = null

var veil         : Control = null
var bubble_label : Label   = null
var tap_label    : Label   = null

var _step       : int   = S_WELCOME
var _t          : float = 0.0
var _busy       : bool  = false
var _free_count : int   = 0

# Public — Game.gd reads this to suspend its own input on gated steps
var gated : bool = false

# Per-step visuals (recomputed in _apply_step)
var _bubble_rect : Rect2       = Rect2(27, 296, 360, 172)
var _mascot_pos  : Vector2     = Vector2.ZERO
var _dim_alpha   : float       = 0.0
var _rings       : Array       = []
var _show_ptr    : bool        = false
var _ptr_tip     : Vector2     = Vector2.ZERO
var _ptr_ang     : float       = 0.0

func begin(g: Node2D, gr: Node) -> void:
	game  = g
	grid  = gr
	layer = 80

	veil = Control.new()
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	veil.draw.connect(_draw_overlay)
	veil.gui_input.connect(_on_veil_input)

	bubble_label = Label.new()
	bubble_label.add_theme_font_size_override("font_size", 19)
	bubble_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bubble_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Fix the wrap width up front so autowrap never computes against a 0-width
	# box (which would wrap to one char per line and push text off-screen)
	bubble_label.custom_minimum_size = Vector2(TEXT_W, 0)
	veil.add_child(bubble_label)

	tap_label = Label.new()
	tap_label.text = "tap to continue"
	tap_label.add_theme_font_size_override("font_size", 14)
	tap_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	tap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tap_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.add_child(tap_label)

	veil.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(veil, "modulate:a", 1.0, 0.30)

	_step = S_WELCOME
	_apply_step()

func _process(delta: float) -> void:
	_t += delta
	if tap_label != null and tap_label.visible:
		tap_label.modulate.a = 0.45 + 0.40 * (sin(_t * 4.0) * 0.5 + 0.5)
	if veil != null:
		veil.queue_redraw()

# ── Step machine ─────────────────────────────────────────────────────────────
func _advance() -> void:
	_step += 1
	if _step != S_WELCOME:
		Sfx.play_click()
	_apply_step()

func _apply_step() -> void:
	var pname : String = GameState.player_name if not GameState.player_name.is_empty() else "PLAYER"
	_busy = false
	_show_ptr = false
	_rings = []
	_dim_alpha = 0.0
	gated = false
	game.tut_unlock()

	match _step:
		S_WELCOME:
			# Board is empty here, so a soft dim is fine and helps the intro pop
			_dim_alpha = 0.45
			gated = true
			_set_bubble("center")
			bubble_label.text = "Hey %s! I'm Cubie. Follow the glowing arrows and I'll show you the ropes." % pname

		S_PLACE1:
			_setup_board()
			_guide_step(0, "Drag this block onto the glowing spot.")

		S_PLACE2:
			_guide_step(1, "Nice! Now this one, right here.")

		S_PLACE3:
			_guide_step(2, "Last one - that's a TRIPLE line clear!")

		S_FREE:
			_free_count = 0
			_set_bubble("bottom")
			bubble_label.text = "Boom! Your turn - place these three anywhere you like."

		S_BOMB:
			game.tut_set_meter(0.32)   # gift a bomb-tier charge
			# Ring the orb (no dim) so the board stays fully visible for the blast
			_rings = [Rect2(POWER_RECT)]
			_point(Vector2(POWER_RECT.end.x + 18.0, POWER_RECT.end.y + 18.0), PI * 1.25)
			_set_bubble("bottom")
			bubble_label.text = "You charged a Power Orb! Tap it to blast the board."

		S_GOODLUCK:
			gated = true
			_set_bubble("bottom")
			bubble_label.text = "You've got it, %s! Good luck out there!" % pname

		S_FINISHED:
			if game != null:
				game.tut_finish()
			return

	_apply_gate()
	_position_ui()

# Configure one of the three guided placements
func _guide_step(idx: int, text: String) -> void:
	var g : Dictionary = GUIDE[idx]
	var slot : int = g["slot"]
	var col  : int = g["col"]
	game.tut_lock(slot, Vector2i(col, 5))   # bar origin at row 5, extends to 7

	# No dim — keep the board fully visible; just ring the target + the piece
	var target := Rect2(GRID_X + float(col) * GRID_STEP - 3.0,
		GRID_Y + 5.0 * GRID_STEP - 3.0, CELL + 6.0, 2.0 * GRID_STEP + CELL + 6.0)
	var tray := Rect2(float(slot) * 138.0 + 12.0, 612.0, 114.0, 150.0)
	_rings = [target, tray]
	_point(Vector2(target.position.x + target.size.x * 0.5, target.position.y - 14.0), PI * 0.5)
	_set_bubble("bottom")
	bubble_label.text = text

func _apply_gate() -> void:
	if veil == null:
		return
	veil.mouse_filter = Control.MOUSE_FILTER_STOP if gated else Control.MOUSE_FILTER_IGNORE

func _on_veil_input(event: InputEvent) -> void:
	if _busy or not gated:
		return
	var tap : bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed)
	if tap:
		veil.accept_event()
		_advance()

# Events forwarded from Game.gd
func on_event(kind: String, lines: int) -> void:
	if _busy:
		return
	match _step:
		S_PLACE1, S_PLACE2:
			if kind == "placed":
				_advance()
		S_PLACE3:
			if kind == "placed":   # the triple clear just fired
				_advance()
		S_FREE:
			if kind == "placed":
				_free_count += 1
				if _free_count >= FREE_TARGET:
					_advance()
				else:
					var left : int = FREE_TARGET - _free_count
					bubble_label.text = "Great! %d more to go - place them wherever you like." % left
		S_BOMB:
			if kind == "power":
				_busy = true
				# Clear all overlay clutter so the bomb drop + blast are fully visible
				_rings = []
				_show_ptr = false
				_dim_alpha = 0.0
				veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
				await game.get_tree().create_timer(1.5).timeout
				if is_instance_valid(self):
					_busy = false
					_advance()

# ── Scripted board (built once, then it's their run) ─────────────────────────
func _setup_board() -> void:
	game.tut_clear_board()
	# Bottom three rows pre-filled in columns 0-4; columns 5-7 are the open gap.
	# The third bar completes all three rows → triple clear empties the board clean.
	for r in range(5, 8):
		for c in 5:
			game.tut_fill_cell(r, c, C_ROW)
	game.tut_set_pieces([BAR, BAR, BAR])

# ── Layout helpers ───────────────────────────────────────────────────────────
func _set_bubble(where: String) -> void:
	match where:
		# Below the tray — never covers the board or the pieces
		"bottom": _bubble_rect = Rect2(27, 780, 360, 104)
		_:        _bubble_rect = Rect2(27, 296, 360, 172)

func _point(tip: Vector2, ang: float) -> void:
	_show_ptr = true
	_ptr_tip = tip
	_ptr_ang = ang

func _position_ui() -> void:
	var br := _bubble_rect
	_mascot_pos = Vector2(br.position.x + 46.0, br.position.y + br.size.y * 0.5 - 4.0)
	bubble_label.position = Vector2(br.position.x + 88.0, br.position.y + 12.0)
	var lh : float = br.size.y - (44.0 if gated else 26.0)
	bubble_label.size = Vector2(br.size.x - 104.0, lh)
	tap_label.visible = gated
	tap_label.position = Vector2(br.position.x, br.end.y - 30.0)
	tap_label.size = Vector2(br.size.x, 24.0)

# ── Drawing ──────────────────────────────────────────────────────────────────
func _draw_overlay() -> void:
	if _dim_alpha > 0.0:
		veil.draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0.03, 0.02, 0.06, _dim_alpha), true)

	for r : Rect2 in _rings:
		_ring(r)

	if _show_ptr:
		_draw_arrow(_ptr_tip, _ptr_ang, 6.0 + (sin(_t * 5.0) * 0.5 + 0.5) * 8.0)

	_draw_bubble()
	_draw_cubie(_mascot_pos, _t)

# Pulsing gold highlight ring
func _ring(r: Rect2) -> void:
	var pulse := sin(_t * 4.0) * 0.5 + 0.5
	var grow := 2.0 + pulse * 2.5
	_rrect_outline(r.grow(grow + 3.0), 12.0, Color(1.0, 0.86, 0.32, 0.16 + 0.14 * pulse), 6.0)
	_rrect_outline(r.grow(grow), 11.0, Color(1.0, 0.88, 0.40, 0.55 + 0.40 * pulse), 3.0)

func _draw_arrow(tip: Vector2, ang: float, bob: float) -> void:
	var dir := Vector2(cos(ang), sin(ang))
	var perp := Vector2(-dir.y, dir.x)
	var t := tip + dir * bob
	var col := Color(1.0, 0.84, 0.24, 0.96)
	var head := 17.0
	var pts := PackedVector2Array([
		t,
		t - dir * head + perp * head * 0.72,
		t - dir * head - perp * head * 0.72,
	])
	veil.draw_colored_polygon(pts, col)
	veil.draw_line(t - dir * head, t - dir * (head + 18.0), col, 6.0)

func _draw_bubble() -> void:
	var r := _bubble_rect
	_rrect(Rect2(r.position + Vector2(0, 5), r.size), 22.0, Color(0, 0, 0, 0.30))
	_rrect(r, 22.0, Color(0.15, 0.13, 0.22, 0.99))
	_rrect_outline(r, 22.0, Color(1, 1, 1, 0.10), 2.0)

# Cubie: a cheerful little block mascot — bobbing, blinking, smiling
func _draw_cubie(c: Vector2, t: float) -> void:
	var bob := sin(t * 3.0) * 3.0
	var p := c + Vector2(0, bob)
	var half := 26.0
	var body := Rect2(p - Vector2(half, half), Vector2(half * 2.0, half * 2.0))
	_rrect(body, 11.0, Color(0.30, 0.82, 0.62))
	_rrect(Rect2(body.position, Vector2(body.size.x, body.size.y * 0.5)), 11.0, Color(0.42, 0.92, 0.72))
	_rrect_outline(body, 11.0, Color(0, 0, 0, 0.18), 2.0)
	veil.draw_circle(p + Vector2(-15, 6), 4.0, Color(1.0, 0.55, 0.65, 0.55))
	veil.draw_circle(p + Vector2( 15, 6), 4.0, Color(1.0, 0.55, 0.65, 0.55))
	var blink : bool = fmod(t, 3.0) < 0.14
	for sx : float in [-1.0, 1.0]:
		var ec := p + Vector2(sx * 9.0, -4.0)
		if blink:
			veil.draw_line(ec + Vector2(-4, 0), ec + Vector2(4, 0), Color(0.1, 0.12, 0.16), 2.5)
		else:
			veil.draw_circle(ec, 6.0, Color.WHITE)
			veil.draw_circle(ec + Vector2(sx * 1.2, 1.5), 3.0, Color(0.10, 0.12, 0.18))
			veil.draw_circle(ec + Vector2(sx * 1.2 - 1.2, 0.2), 1.1, Color(1, 1, 1, 0.9))
	veil.draw_arc(p + Vector2(0, 6), 8.0, deg_to_rad(20.0), deg_to_rad(160.0), 14,
		Color(0.10, 0.12, 0.18), 2.5, true)

# ── Rounded-rect helpers ─────────────────────────────────────────────────────
func _rrect_pts(r: Rect2, rad: float) -> PackedVector2Array:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	var pts := PackedVector2Array()
	var corners := [
		[r.position + Vector2(rad, rad),             PI,       PI * 1.5],
		[Vector2(r.end.x - rad, r.position.y + rad), PI * 1.5, TAU],
		[r.end - Vector2(rad, rad),                  0.0,      PI * 0.5],
		[Vector2(r.position.x + rad, r.end.y - rad), PI * 0.5, PI],
	]
	for cn in corners:
		for i in 5:
			var a : float = lerpf(cn[1], cn[2], float(i) / 4.0)
			pts.append(cn[0] + Vector2(cos(a), sin(a)) * rad)
	return pts

func _rrect(r: Rect2, rad: float, col: Color) -> void:
	veil.draw_colored_polygon(_rrect_pts(r, rad), col)

func _rrect_outline(r: Rect2, rad: float, col: Color, width: float) -> void:
	var pts := _rrect_pts(r, rad)
	pts.append(pts[0])
	veil.draw_polyline(pts, col, width)
