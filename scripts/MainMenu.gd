extends Node2D

# Intro screen: floating orbs + falling cartoon blocks behind an animated
# bouncing STAX logo, chunky PLAY / SETTINGS buttons, inline settings panel.

const COLORS: Array = [
	Color(0.32, 0.80, 0.97),
	Color(1.00, 0.63, 0.28),
	Color(0.95, 0.36, 0.68),
	Color(0.33, 0.90, 0.55),
	Color(0.73, 0.43, 0.97),
	Color(0.97, 0.88, 0.32),
]

const ORB_COUNT := 10
const FALL_COUNT := 12

# In-app review prompt → store deep links. FILL THESE IN once the listings exist:
#   IOS_APP_ID      = the App Store numeric id (App Store Connect), e.g. "1234567890"
#   ANDROID_PACKAGE = your applicationId, e.g. "com.lotus.stax"
# Ratings of REVIEW_STORE_THRESHOLD+ stars open the store write-review page;
# lower ratings just thank the player (keeps low scores off the public listing).
const IOS_APP_ID             := "6778501101"
const ANDROID_PACKAGE        := ""
const REVIEW_STORE_THRESHOLD := 4
# Custom-drawn rating stars (cuter than a glyph + tap-to-fill interaction)
const STAR_COUNT := 5
const STAR_GAP   := 56.0
const STAR_R     := 23.0

const SKIN_NAMES : Array = ["PASTEL", "NEON", "CIRCUIT", "BRICK", "CRYSTAL",
	"CANDY", "FROST", "GRASS", "WATER", "LAVA", "WOOD", "GALAXY",
	"HONEY", "RETRO", "BUBBLE", "STORM", "SAKURA", "METALS", "SLIME", "DISCO",
	"AURORA", "PLASMA", "MARBLE", "MATRIX", "HOLOGRAM",
	"PRISM", "STAINED", "SYNTHWAVE", "AUTUMN", "WARP"]

var orbs    : Array = []
var fallers : Array = []
var time_t  : float = 0.0

var letters      : Array = []   # {lbl, base_pos, phase}
var bobbing      : bool  = false
var cat_progress : int   = 0    # secret: tap S-T-A-X in order to toggle cat mode
var settings_box : PanelContainer
var play_pulse   : Tween
var faller_layer : Node2D

@onready var ui : CanvasLayer = $UI

func _ready() -> void:
	for _i in ORB_COUNT:
		orbs.append({
			"pos":    Vector2(randf() * 414.0, randf() * 896.0),
			"vel":    Vector2((randf() - 0.5) * 18.0, (randf() - 0.5) * 18.0),
			"radius": randf_range(60.0, 140.0),
			"color":  Color(0.55, 0.55, 1.0, randf_range(0.04, 0.09)),
		})
	for _i in FALL_COUNT:
		fallers.append(_make_faller(true))

	# Fallers paint on their own translucent layer so full skin detail
	# can render without overpowering the menu
	faller_layer = Node2D.new()
	faller_layer.modulate = Color(1, 1, 1, 0.55)
	add_child(faller_layer)
	faller_layer.draw.connect(_draw_fallers)

	# Account sign-in feedback (autoload signals; this instance is fresh each load)
	Auth.signed_in.connect(_on_auth_signed_in)
	Auth.sign_in_failed.connect(_on_auth_failed)
	Auth.signed_out.connect(_on_auth_signed_out)

	# First open: only the animated background + name prompt. The menu builds
	# (and the logo intro plays) after the name is confirmed.
	if GameState.player_name.is_empty():
		_build_name_prompt()
	else:
		_build_menu()
	Sfx.update_music()

func _build_menu() -> void:
	_build_logo()
	_build_profile()
	_build_buttons()
	_build_settings_panel()
	_build_achievements_panel()
	_build_biomes_panel()
	_build_leaderboard_panel()
	_build_stats_panel()
	_maybe_show_review()
	# Silently refresh the player's global rank so the profile pin is up to date
	if Net.is_configured():
		Net.fetch_global(50)

func _make_faller(anywhere: bool) -> Dictionary:
	return {
		"pos":   Vector2(randf() * 414.0, (randf() * 896.0) if anywhere else -80.0),
		"spd":   randf_range(22.0, 55.0),
		"rot":   randf() * TAU,
		"rspd":  randf_range(-0.8, 0.8),
		"cs":    randf_range(11.0, 17.0),   # cell size of the mini piece
		"shape": BlockSkins.DEMO_SHAPES[randi() % BlockSkins.DEMO_SHAPES.size()],
		"seed":  randi() % 97,
		"color": COLORS[randi() % COLORS.size()],
	}

# Current skin for menu decoration (cat > dev > player lock > theme rotation)
func _menu_skin() -> int:
	return GameState.effective_skin(GameState.theme_idx)

func _draw_fallers() -> void:
	var style := _menu_skin()
	for f in fallers:
		faller_layer.draw_set_transform(f["pos"], f["rot"])
		var cs : float = f["cs"]
		for cell in f["shape"]:
			BlockSkins.paint(faller_layer, style,
				Rect2(cell[0] * cs, cell[1] * cs, cs - 1.0, cs - 1.0),
				f["color"], f["seed"] + cell[0] * 7 + cell[1] * 13)
	faller_layer.draw_set_transform(Vector2.ZERO)

func _process(delta: float) -> void:
	time_t += delta
	for orb in orbs:
		orb["pos"] += orb["vel"] * delta
		if orb["pos"].x < -140.0 or orb["pos"].x > 554.0: orb["vel"].x = -orb["vel"].x
		if orb["pos"].y < -140.0 or orb["pos"].y > 1036.0: orb["vel"].y = -orb["vel"].y
	for i in fallers.size():
		var f : Dictionary = fallers[i]
		f["pos"].y += f["spd"] * delta
		f["rot"]   += f["rspd"] * delta
		if f["pos"].y > 950.0:
			fallers[i] = _make_faller(false)

	if bobbing:
		for i in letters.size():
			var entry : Dictionary = letters[i]
			var lbl   : Label      = entry["lbl"]
			lbl.position.y = entry["base_pos"].y + sin(time_t * 2.2 + entry["phase"]) * 7.0
			lbl.rotation_degrees = sin(time_t * 1.6 + entry["phase"]) * 3.0

	queue_redraw()
	faller_layer.queue_redraw()

	# Keep animated biome previews alive while the gallery is open
	if biome_box != null and biome_box.visible:
		for sw in biome_swatches:
			if is_instance_valid(sw):
				sw.queue_redraw()

# ── Background drawing — follows the selected skin's theme live ─────────────
func _draw() -> void:
	var theme_data : Dictionary = GameState.THEMES[_menu_skin() % GameState.THEMES.size()]
	draw_rect(Rect2(Vector2.ZERO, Vector2(414, 896)), theme_data["bg"], true)
	var oc : Color = theme_data["orb"]
	for orb in orbs:
		draw_circle(orb["pos"], orb["radius"],
			Color(oc.r, oc.g, oc.b, orb["color"].a))
	# Cat mode: paw prints drifting up the menu
	if GameState.cat_mode:
		var paw := Color(1.0, 0.80, 0.88, 0.08)
		for i in 8:
			var pxp : float = fmod(float(i * 131 + 37) * 29.7, 414.0)
			var pyp : float = fmod(float(i * 89 + 17) * 47.3 - time_t * (8.0 + float(i % 3) * 4.0), 940.0) - 22.0
			if pyp < -22.0: pyp += 940.0
			draw_circle(Vector2(pxp, pyp), 8.0, paw)
			for j in 4:
				var a := -PI * 0.5 + (float(j) - 1.5) * 0.5
				draw_circle(Vector2(pxp, pyp) + Vector2(cos(a), sin(a)) * 12.0, 3.5, paw)

# ── Logo ──────────────────────────────────────────────────────────────────────
func _build_logo() -> void:
	var text    := "STAX"
	var lw      := 78.0
	var start_x := (414.0 - lw * text.length()) * 0.5
	for i in text.length():
		var lbl := Label.new()
		lbl.text = text[i]
		lbl.add_theme_font_size_override("font_size", 96)
		lbl.add_theme_color_override("font_color", COLORS[i % COLORS.size()])
		lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.09))
		lbl.add_theme_constant_override("outline_size", 14)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.size = Vector2(lw, 120)
		lbl.pivot_offset = Vector2(lw * 0.5, 60)
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP   # secret: each letter is tappable
		var base := Vector2(start_x + i * lw, 130.0)
		lbl.position = base - Vector2(0, 320)   # start off-screen above
		ui.add_child(lbl)
		letters.append({"lbl": lbl, "base_pos": base, "phase": float(i) * 0.8})
		var li := i
		lbl.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_on_letter_tapped(li))

		# Drop in with overshoot, staggered
		var t := create_tween()
		t.tween_interval(0.15 + float(i) * 0.12)
		t.tween_property(lbl, "position", base, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if i == letters.size() - 1 and text.length() - 1 == i:
			t.tween_callback(func(): bobbing = true)

	# Best score lives in the profile card now (folded out of the waterfall)

# ── Secret cat easter egg: tap the letters S-T-A-X in order ──────────────────
func _on_letter_tapped(idx: int) -> void:
	# Tapped letter does a happy hop
	var lbl : Label = letters[idx]["lbl"]
	var hop := create_tween()
	hop.tween_property(lbl, "scale", Vector2(1.3, 1.3), 0.10).set_trans(Tween.TRANS_BACK)
	hop.tween_property(lbl, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK)
	if GameState.haptics_on:
		Input.vibrate_handheld(15)
	if idx == cat_progress:
		cat_progress += 1
		Sfx.play_tick()
		if cat_progress >= letters.size():
			cat_progress = 0
			_toggle_cat_mode()
	else:
		# Wrong order — start over (but a first-letter tap still counts)
		cat_progress = 1 if idx == 0 else 0

func _toggle_cat_mode() -> void:
	# The bg, orbs and falling pieces all read the skin live each frame, so the
	# whole menu recolours to (or from) the cat theme instantly — no rebuild.
	GameState.set_cat_mode(not GameState.cat_mode)
	Sfx.play_meow()
	_show_meow_popup()
	# Letters do a happy scale-pop to celebrate (rotation is owned by the bob)
	for i in letters.size():
		var l : Label = letters[i]["lbl"]
		var t := create_tween()
		t.tween_interval(float(i) * 0.06)
		t.tween_property(l, "scale", Vector2(1.4, 1.4), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(l, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK)

func _show_meow_popup() -> void:
	var lbl := Label.new()
	lbl.text = "MEOW!" if GameState.cat_mode else "BYE KITTY"
	lbl.add_theme_font_size_override("font_size", 64)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.78, 0.88))
	lbl.add_theme_color_override("font_outline_color", Color(0.2, 0.1, 0.18))
	lbl.add_theme_constant_override("outline_size", 10)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size = Vector2(414, 90)
	lbl.position = Vector2(0, 400)
	lbl.pivot_offset = Vector2(207, 45)
	lbl.scale = Vector2(0.2, 0.2)
	ui.add_child(lbl)
	var t := create_tween()
	t.tween_property(lbl, "scale", Vector2(1.15, 1.15), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(lbl, "scale", Vector2.ONE, 0.12)
	t.tween_interval(0.7)
	t.tween_property(lbl, "modulate:a", 0.0, 0.4)
	t.tween_callback(lbl.queue_free)

# ── In-app review prompt (after the tutorial's first full run) ───────────────
var review_overlay : Control
var review_stars   : Control
var _star_fill     : float = 0.0   # animated number of filled stars (0..5)
var _star_locked   : bool  = false # true once a rating is committed

func _maybe_show_review() -> void:
	if not GameState.should_ask_review():
		return
	# Let the menu settle in first, then slide the ask up
	var t := create_tween()
	t.tween_interval(0.7)
	t.tween_callback(_show_review_prompt)

func _show_review_prompt() -> void:
	if review_overlay != null and is_instance_valid(review_overlay):
		return
	review_overlay = Control.new()
	review_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	review_overlay.mouse_filter = Control.MOUSE_FILTER_STOP   # swallow taps behind it
	ui.add_child(review_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	review_overlay.add_child(dim)
	create_tween().tween_property(dim, "color", Color(0, 0, 0, 0.6), 0.25)

	var box := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.13, 0.11, 0.20)
	psb.set_corner_radius_all(24)
	psb.border_width_bottom = 8
	psb.border_color = Color(0.06, 0.05, 0.10)
	psb.content_margin_left = 22; psb.content_margin_right = 22
	psb.content_margin_top = 20;  psb.content_margin_bottom = 22
	box.add_theme_stylebox_override("panel", psb)
	box.position = Vector2(37, 250)
	box.custom_minimum_size = Vector2(340, 0)
	box.pivot_offset = Vector2(170, 150)
	box.scale = Vector2(0.85, 0.85)
	review_overlay.add_child(box)
	create_tween().tween_property(box, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	box.add_child(vbox)

	var title := Label.new()
	title.text = "ENJOYING STAX?"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1, 0.92, 0.6))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var body := Label.new()
	body.text = "Leaving a review really helps a small game like ours grow. Hope you're having fun!"
	body.add_theme_font_size_override("font_size", 16)
	body.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(296, 0)
	vbox.add_child(body)

	review_stars = Control.new()
	review_stars.custom_minimum_size = Vector2(280, 74)
	review_stars.size_flags_horizontal = Control.SIZE_FILL
	review_stars.mouse_filter = Control.MOUSE_FILTER_STOP
	_star_fill = 0.0
	_star_locked = false
	vbox.add_child(review_stars)
	review_stars.draw.connect(_draw_review_stars)
	review_stars.gui_input.connect(_on_star_input)

	var later := _make_chunky_button("MAYBE LATER", Color(0.40, 0.55, 0.95), 16)
	later.custom_minimum_size = Vector2(0, 46)
	later.pressed.connect(func():
		Sfx.play_click()
		GameState.snooze_review()
		_close_review())
	vbox.add_child(later)

	var never := Button.new()
	never.text = "Don't ask again"
	never.flat = true
	never.add_theme_font_size_override("font_size", 14)
	never.add_theme_color_override("font_color", Color(1, 1, 1, 0.50))
	never.add_theme_color_override("font_hover_color", Color(1, 1, 1, 0.75))
	never.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	never.pressed.connect(func():
		Sfx.play_click()
		GameState.finish_review()
		_close_review())
	vbox.add_child(never)

# ── Cute custom rating stars ─────────────────────────────────────────────────
# A soft, bubbly 5-point star: every corner (tips AND inner valleys) is rounded
# off with a little quadratic-bezier fillet, so nothing reads as sharp.
func _bubbly_star_points(center: Vector2, r_out: float, r_in: float, round_amt: float) -> PackedVector2Array:
	var base : Array = []
	for k in 10:
		var ang := -PI / 2.0 + float(k) * PI / 5.0
		var rad := r_out if k % 2 == 0 else r_in
		base.append(center + Vector2(cos(ang), sin(ang)) * rad)
	var pts := PackedVector2Array()
	var n := base.size()
	for k in n:
		var cur  : Vector2 = base[k]
		var prev : Vector2 = base[(k - 1 + n) % n]
		var nxt  : Vector2 = base[(k + 1) % n]
		var d := minf((prev - cur).length(), (nxt - cur).length()) * round_amt
		var p_a := cur + (prev - cur).normalized() * d
		var p_b := cur + (nxt - cur).normalized() * d
		var steps := 6
		for s in steps + 1:
			var t := float(s) / float(steps)
			# quadratic bezier p_a → cur (control) → p_b rounds the corner
			pts.append(p_a.lerp(cur, t).lerp(cur.lerp(p_b, t), t))
	return pts

func _draw_review_stars() -> void:
	var total_w := STAR_GAP * float(STAR_COUNT - 1)
	var x0 := (review_stars.size.x - total_w) * 0.5
	var cy := review_stars.size.y * 0.5
	for i in STAR_COUNT:
		var a := clampf(_star_fill - float(i), 0.0, 1.0)        # 0 empty → 1 full
		var sc := 0.84 + 0.16 * a                                # filled stars sit a touch bigger
		var center := Vector2(x0 + float(i) * STAR_GAP, cy)
		var r := STAR_R * sc
		var hue : Color = COLORS[i % COLORS.size()]              # rainbow, matching the logo
		var pts := _bubbly_star_points(center, r, r * 0.55, 0.5)
		# Soft halo behind a lit star — fakes a glow without a blur pass
		if a > 0.02:
			var halo := _bubbly_star_points(center, r * 1.18, r * 1.18 * 0.55, 0.5)
			review_stars.draw_colored_polygon(halo, Color(hue.r, hue.g, hue.b, 0.18 * a))
		# Body: faint tinted outline when empty → full colour when filled
		var fill := Color(hue.r, hue.g, hue.b, 0.12).lerp(hue, a)
		review_stars.draw_colored_polygon(pts, fill)
		# Gentle colour-matched outline (no harsh black edge)
		var outline := pts.duplicate()
		outline.append(pts[0])
		var ol_col := Color(hue.r, hue.g, hue.b, 0.35).lerp(hue.darkened(0.30), a)
		review_stars.draw_polyline(outline, ol_col, 2.5, true)
		# Bubbly gloss highlight
		if a > 0.05:
			review_stars.draw_circle(center + Vector2(-r * 0.26, -r * 0.32), r * 0.18, Color(1, 1, 1, 0.6 * a))

func _star_at(x: float) -> int:
	var total_w := STAR_GAP * float(STAR_COUNT - 1)
	var x0 := (review_stars.size.x - total_w) * 0.5
	return clampi(int(round((x - x0) / STAR_GAP)), 0, STAR_COUNT - 1)

func _set_star_fill(v: float) -> void:
	_star_fill = v
	if is_instance_valid(review_stars):
		review_stars.queue_redraw()

func _on_star_input(ev: InputEvent) -> void:
	if _star_locked:
		return
	if ev is InputEventMouseMotion or ev is InputEventScreenDrag:
		_set_star_fill(float(_star_at(ev.position.x) + 1))   # hover/drag previews the fill
	elif (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) \
			or (ev is InputEventScreenTouch and ev.pressed):
		_select_star(_star_at(ev.position.x) + 1)

func _select_star(n: int) -> void:
	if _star_locked:
		return
	_star_locked = true
	Sfx.play_tick()
	var t := create_tween()
	# Sweep the fill up to the chosen star…
	t.tween_method(_set_star_fill, _star_fill, float(n), 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# …then a happy pop of the whole row
	t.tween_callback(func():
		review_stars.pivot_offset = review_stars.size * 0.5
		var p := create_tween()
		p.tween_property(review_stars, "scale", Vector2(1.12, 1.12), 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		p.tween_property(review_stars, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK))
	t.tween_interval(0.34)
	t.tween_callback(func(): _on_review_star(n))

func _on_review_star(n: int) -> void:
	GameState.finish_review()       # asked + answered → never auto-ask again
	if n >= REVIEW_STORE_THRESHOLD:
		_open_store_review()
	_close_review()

func _open_store_review() -> void:
	var url := ""
	match OS.get_name():
		"iOS":
			if IOS_APP_ID != "":
				url = "itms-apps://itunes.apple.com/app/id" + IOS_APP_ID + "?action=write-review"
		"Android":
			if ANDROID_PACKAGE != "":
				url = "market://details?id=" + ANDROID_PACKAGE
		_:
			if IOS_APP_ID != "":   # desktop dev fallback — open the web listing
				url = "https://apps.apple.com/app/id" + IOS_APP_ID
	if url != "":
		OS.shell_open(url)

func _close_review() -> void:
	if review_overlay == null or not is_instance_valid(review_overlay):
		return
	var ov := review_overlay
	review_overlay = null
	var t := create_tween()
	t.tween_property(ov, "modulate:a", 0.0, 0.2)
	t.tween_callback(ov.queue_free)

# ── Player profile card: name + level chip + XP bar + best, tap for stats ───
var profile_name : Label
var profile_chip : Label
var profile_best : Label
var profile_pin  : Control
var xp_fill      : Panel
var xp_text      : Label

const XP_BAR_W := 268.0

func _build_profile() -> void:
	var card := Button.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.28)
	sb.set_corner_radius_all(18)
	var sb_hover := sb.duplicate()
	sb_hover.bg_color = Color(0, 0, 0, 0.38)
	var sb_press := sb.duplicate()
	sb_press.bg_color = Color(0, 0, 0, 0.45)
	card.add_theme_stylebox_override("normal", sb)
	card.add_theme_stylebox_override("hover", sb_hover)
	card.add_theme_stylebox_override("pressed", sb_press)
	card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	card.size = Vector2(300, 96)
	card.position = Vector2(57, 300)
	ui.add_child(card)
	card.pressed.connect(func():
		Sfx.play_click()
		_open_stats())
	_add_press_effect(card)

	# Global-rank pin sits left of the name (only shown once a rank is known)
	profile_pin = Control.new()
	profile_pin.custom_minimum_size = Vector2(30, 30)
	profile_pin.size = Vector2(30, 30)
	profile_pin.position = Vector2(13, 4)
	profile_pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	profile_pin.draw.connect(func():
		var t := _rank_tier(GameState.my_global_rank)
		if t > 0:
			_draw_pin(profile_pin, Vector2(15, 15), 12.0, t))
	card.add_child(profile_pin)

	profile_name = Label.new()
	profile_name.add_theme_font_size_override("font_size", 20)
	profile_name.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	profile_name.position = Vector2(16, 6)
	profile_name.size = Vector2(190, 28)
	card.add_child(profile_name)

	profile_chip = Label.new()
	profile_chip.add_theme_font_size_override("font_size", 14)
	profile_chip.add_theme_color_override("font_color", Color(0.10, 0.08, 0.05))
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.95, 0.78, 0.20)
	csb.set_corner_radius_all(10)
	csb.content_margin_left = 10; csb.content_margin_right = 10
	csb.content_margin_top = 3;   csb.content_margin_bottom = 3
	profile_chip.add_theme_stylebox_override("normal", csb)
	profile_chip.position = Vector2(222, 9)
	card.add_child(profile_chip)

	var track := Panel.new()
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0, 0, 0, 0.40)
	tsb.set_corner_radius_all(6)
	track.add_theme_stylebox_override("panel", tsb)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.position = Vector2(16, 42)
	track.size = Vector2(XP_BAR_W, 12)
	card.add_child(track)

	xp_fill = Panel.new()
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.95, 0.78, 0.20)
	fsb.set_corner_radius_all(6)
	xp_fill.add_theme_stylebox_override("panel", fsb)
	xp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_fill.position = Vector2(16, 42)
	card.add_child(xp_fill)

	profile_best = Label.new()
	profile_best.add_theme_font_size_override("font_size", 13)
	profile_best.add_theme_color_override("font_color", Color(0.95, 0.85, 0.15, 0.90))
	profile_best.position = Vector2(16, 62)
	profile_best.size = Vector2(160, 22)
	card.add_child(profile_best)

	xp_text = Label.new()
	xp_text.add_theme_font_size_override("font_size", 12)
	xp_text.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	xp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	xp_text.position = Vector2(144, 63)
	xp_text.size = Vector2(140, 20)
	card.add_child(xp_text)

	_refresh_profile()

func _refresh_profile() -> void:
	profile_name.text = GameState.player_name if not GameState.player_name.is_empty() else "PLAYER"
	# Slide the name right when a rank pin is showing, flush-left when it isn't
	var has_pin := _rank_tier(GameState.my_global_rank) > 0
	profile_name.position.x = 48.0 if has_pin else 16.0
	if is_instance_valid(profile_pin):
		profile_pin.queue_redraw()
	var lvl := GameState.get_level()
	profile_chip.text = "LV " + str(lvl)
	profile_best.text = ("BEST  " + _fmt_num(GameState.best_score)) if GameState.best_score > 0 else "NO RUNS YET"
	if lvl >= GameState.MAX_LEVEL:
		xp_fill.size = Vector2(XP_BAR_W, 12)
		xp_text.text = "MAX LEVEL"
	else:
		var prog : Array = GameState.xp_progress()
		var frac : float = clampf(float(prog[0]) / float(maxi(prog[1], 1)), 0.0, 1.0)
		xp_fill.size = Vector2(maxf(XP_BAR_W * frac, 12.0 if prog[0] > 0 else 0.0), 12)
		xp_text.text = str(prog[0]) + " / " + str(prog[1]) + " XP"

# ── First-open name prompt ────────────────────────────────────────────────────
func _build_name_prompt() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.70)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(dim)

	var panel := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.13, 0.11, 0.20)
	psb.set_corner_radius_all(24)
	psb.border_width_bottom = 8
	psb.border_color = Color(0.06, 0.05, 0.10)
	psb.content_margin_left = 28; psb.content_margin_right = 28
	psb.content_margin_top = 24;  psb.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", psb)
	panel.position = Vector2(47, 300)
	panel.custom_minimum_size = Vector2(320, 0)
	ui.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "WHAT'S YOUR NAME?"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var input := LineEdit.new()
	input.max_length = 12
	input.placeholder_text = "PLAYER"
	input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	input.add_theme_font_size_override("font_size", 22)
	input.custom_minimum_size = Vector2(0, 52)
	vbox.add_child(input)

	var go := _make_chunky_button("LET'S GO", Color(0.20, 0.85, 0.45), 22)
	go.custom_minimum_size = Vector2(0, 56)
	vbox.add_child(go)

	var confirm := func():
		var n := input.text.strip_edges()
		GameState.set_player_name(n if not n.is_empty() else "PLAYER")
		Sfx.play_click()
		dim.queue_free()
		panel.queue_free()
		# Brand-new player → drop them straight into the coached tutorial game.
		# Once it's been completed, naming just builds the menu as normal.
		if not GameState.tutorial_done:
			GameState.tutorial_active = true
			GameState.has_save = false
			GameState.clear_run()
			get_tree().change_scene_to_file("res://scenes/Game.tscn")
		else:
			_build_menu()   # menu intro plays now, on a clean screen
	go.pressed.connect(confirm)
	input.text_submitted.connect(func(_t): confirm.call())
	input.grab_focus()

# ── Stats panel (opened from the profile card) ───────────────────────────────
var stats_box  : PanelContainer
var stats_grid : GridContainer
var stats_sub  : Label
var stats_pin  : Control
var stats_name : Label

func _build_stats_panel() -> void:
	stats_box = PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.13, 0.11, 0.20)
	psb.set_corner_radius_all(24)
	psb.border_width_bottom = 8
	psb.border_color = Color(0.06, 0.05, 0.10)
	psb.content_margin_left = 18; psb.content_margin_right = 18
	psb.content_margin_top = 16;  psb.content_margin_bottom = 20
	stats_box.add_theme_stylebox_override("panel", psb)
	stats_box.position = Vector2(22, 160)
	stats_box.custom_minimum_size = Vector2(370, 0)
	stats_box.visible = false
	ui.add_child(stats_box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	stats_box.add_child(vbox)

	var title := Label.new()
	title.text = "STATS"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Name + rank pin, kept side-by-side so the badge reads as part of the name
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 8)
	vbox.add_child(name_row)
	stats_pin = Control.new()
	stats_pin.custom_minimum_size = Vector2(34, 34)
	stats_pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_pin.draw.connect(func():
		var t := _rank_tier(GameState.my_global_rank)
		if t > 0:
			_draw_pin(stats_pin, Vector2(17, 17), 13.0, t))
	name_row.add_child(stats_pin)
	stats_name = Label.new()
	stats_name.add_theme_font_size_override("font_size", 22)
	stats_name.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	stats_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_row.add_child(stats_name)

	stats_sub = Label.new()
	stats_sub.add_theme_font_size_override("font_size", 13)
	stats_sub.add_theme_color_override("font_color", Color(0.95, 0.78, 0.20, 0.90))
	stats_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(stats_sub)

	stats_grid = GridContainer.new()
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", 10)
	stats_grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(stats_grid)

	var close := _make_chunky_button("CLOSE", Color(0.90, 0.30, 0.40), 18)
	close.custom_minimum_size = Vector2(0, 50)
	close.pressed.connect(func():
		Sfx.play_click()
		stats_box.visible = false)
	vbox.add_child(close)

func _populate_stats() -> void:
	for child in stats_grid.get_children():
		child.queue_free()
	var pname := GameState.player_name if not GameState.player_name.is_empty() else "PLAYER"
	stats_name.text = pname
	stats_pin.visible = _rank_tier(GameState.my_global_rank) > 0
	stats_pin.queue_redraw()
	stats_sub.text = "LEVEL " + str(GameState.get_level()) \
		+ "   ·   " + _fmt_num(GameState.player_xp) + " TOTAL XP"
	var stats : Array = [
		[_fmt_num(GameState.games_played),      "GAMES PLAYED"],
		[_fmt_num(GameState.best_score),        "HIGHEST SCORE"],
		[_fmt_num(GameState.total_score),       "TOTAL SCORE"],
		[_fmt_num(GameState.total_lines),       "LINES CLEARED"],
		[_fmt_num(GameState.stat_best_streak),  "LONGEST STREAK"],
		[_fmt_num(GameState.stat_run_lines),    "MOST LINES IN A RUN"],
		[_fmt_num(GameState.stat_blocks),       "BLOCKS PLACED"],
		[_fmt_num(GameState.stat_board_clears), "BOARD CLEARS"],
	]
	for s in stats:
		var tile := Panel.new()
		var tsb := StyleBoxFlat.new()
		tsb.bg_color = Color(1, 1, 1, 0.05)
		tsb.set_corner_radius_all(14)
		tile.add_theme_stylebox_override("panel", tsb)
		tile.custom_minimum_size = Vector2(162, 62)
		var v := Label.new()
		v.text = s[0]
		v.add_theme_font_size_override("font_size", 21)
		v.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.position = Vector2(0, 6)
		v.size = Vector2(162, 30)
		tile.add_child(v)
		var c := Label.new()
		c.text = s[1]
		c.add_theme_font_size_override("font_size", 10)
		c.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.position = Vector2(0, 38)
		c.size = Vector2(162, 16)
		tile.add_child(c)
		stats_grid.add_child(tile)

func _open_stats() -> void:
	_populate_stats()
	stats_box.visible = true
	stats_box.scale = Vector2(0.85, 0.85)
	stats_box.pivot_offset = Vector2(185, 240)
	var t := create_tween()
	t.tween_property(stats_box, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ── Achievements panel (tiered: card shows current tier, tap to expand) ──────
var ach_box      : PanelContainer
var ach_rows     : VBoxContainer
var ach_expanded : Dictionary = {}   # group id -> bool

# ── Biomes (skins) gallery ───────────────────────────────────────────────────
var biome_box      : PanelContainer
var biome_rows     : VBoxContainer
var biome_mode_btn : Button
var biome_hint     : Label
var biome_swatches : Array = []   # preview Controls redrawn each frame

# ── Online leaderboard + friends ─────────────────────────────────────────────
var lb_box        : PanelContainer
var lb_rows       : VBoxContainer
var lb_status     : Label
var lb_global_btn : Button
var lb_friends_btn: Button
var lb_code_input : LineEdit
var lb_tab        : String = "global"   # "global" | "friends"

# Swipe-to-switch between the leaderboard tabs (mirrors Game.gd's touch pattern)
const LB_TABS : Array[String] = ["global", "friends"]
const LB_SWIPE_MIN := 60.0
var _lb_swipe_start : Vector2 = Vector2.ZERO
var _lb_swiping     : bool    = false

func _input(event: InputEvent) -> void:
	if lb_box == null or not lb_box.visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_lb_swipe_start = event.position
			_lb_swiping = true
		elif _lb_swiping:
			_lb_swiping = false
			_try_lb_swipe(event.position - _lb_swipe_start)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_lb_swipe_start = event.position
			_lb_swiping = true
		elif _lb_swiping:
			_lb_swiping = false
			_try_lb_swipe(event.position - _lb_swipe_start)

func _try_lb_swipe(delta: Vector2) -> void:
	# Only a clearly-horizontal drag past the threshold counts (leaves vertical
	# list scrolling untouched). Swipe left → next tab, swipe right → previous.
	if absf(delta.x) < LB_SWIPE_MIN or absf(delta.x) < absf(delta.y) * 1.2:
		return
	var idx := LB_TABS.find(lb_tab)
	if idx < 0: idx = 0
	var step := 1 if delta.x < 0.0 else -1
	var new_idx := clampi(idx + step, 0, LB_TABS.size() - 1)
	if new_idx != idx:
		Sfx.play_click()
		_set_lb_tab(LB_TABS[new_idx])

func _build_achievements_panel() -> void:
	ach_box = PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.13, 0.11, 0.20)
	psb.set_corner_radius_all(24)
	psb.border_width_bottom = 8
	psb.border_color = Color(0.06, 0.05, 0.10)
	psb.content_margin_left = 18; psb.content_margin_right = 18
	psb.content_margin_top = 16;  psb.content_margin_bottom = 20
	ach_box.add_theme_stylebox_override("panel", psb)
	ach_box.position = Vector2(22, 70)
	ach_box.custom_minimum_size = Vector2(370, 0)
	ach_box.visible = false
	ui.add_child(ach_box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	ach_box.add_child(vbox)

	var title := Label.new()
	title.text = "ACHIEVEMENTS"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(334, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	ach_rows = VBoxContainer.new()
	ach_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ach_rows.add_theme_constant_override("separation", 8)
	scroll.add_child(ach_rows)

	var close := _make_chunky_button("CLOSE", Color(0.90, 0.30, 0.40), 18)
	close.custom_minimum_size = Vector2(0, 50)
	close.pressed.connect(func():
		Sfx.play_click()
		ach_box.visible = false)
	vbox.add_child(close)

# Rebuilt on every open / expand-toggle so progress is always current
func _populate_achievements() -> void:
	for child in ach_rows.get_children():
		child.queue_free()
	for g in GameState.ACH_GROUPS:
		ach_rows.add_child(_make_ach_card(g))
		if ach_expanded.get(g["id"], false):
			ach_rows.add_child(_make_tier_list(g))

# First locked tier index, or tiers.size() when the whole ladder is done
func _ach_current_tier(g: Dictionary) -> int:
	for ti in g["tiers"].size():
		if not GameState.unlocked.get("%s_%d" % [g["id"], ti], false):
			return ti
	return g["tiers"].size()

func _ach_desc(g: Dictionary, target: int) -> String:
	var d : String = g["desc"]
	@warning_ignore("static_called_on_instance")
	return (d % GameState.fmt(target)) if d.contains("%s") else d

func _make_ach_card(g: Dictionary) -> PanelContainer:
	var tiers : Array = g["tiers"]
	var cur   := _ach_current_tier(g)
	var done  := cur >= tiers.size()
	var shown : int = mini(cur, tiers.size() - 1)
	var target : int = tiers[shown][0]
	var v := GameState.ach_value(g["id"])

	# PanelContainer for layout (Buttons don't size child containers);
	# tap-to-expand handled via gui_input
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.95, 0.78, 0.20, 0.12) if done else Color(1, 1, 1, 0.04)
	sb.set_corner_radius_all(14)
	if done:
		sb.border_width_left = 5
		sb.border_color = Color(0.95, 0.78, 0.20)
	sb.content_margin_left = 14; sb.content_margin_right = 12
	sb.content_margin_top = 10;  sb.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", sb)
	# PASS (not STOP) so a touch-drag starting on a card still reaches the
	# ScrollContainer and scrolls the list. Toggle only on a TAP — a press and
	# release with little movement — so scrolling never expands a card.
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.set_meta("moved", false)
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				card.set_meta("press_pos", ev.position)
				card.set_meta("moved", false)
			elif not card.get_meta("moved", false):
				Sfx.play_click()
				ach_expanded[g["id"]] = not ach_expanded.get(g["id"], false)
				_populate_achievements()
		elif ev is InputEventMouseMotion and card.has_meta("press_pos"):
			if ev.position.distance_to(card.get_meta("press_pos")) > 12.0:
				card.set_meta("moved", true))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(h)

	# Medal disc with the tier numeral (gold once the ladder is complete)
	var medal := Panel.new()
	var msb := StyleBoxFlat.new()
	msb.set_corner_radius_all(17)
	if done:
		msb.bg_color = Color(0.95, 0.78, 0.20)
		msb.set_border_width_all(3)
		msb.border_color = Color(1.0, 0.92, 0.55)
	else:
		msb.bg_color = Color(0, 0, 0, 0.30)
		msb.set_border_width_all(2)
		msb.border_color = Color(1, 1, 1, 0.15)
	medal.add_theme_stylebox_override("panel", msb)
	medal.custom_minimum_size = Vector2(34, 34)
	medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	medal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var numeral := Label.new()
	numeral.text = GameState.TIER_NUMERALS[shown] if tiers.size() > 1 else "I"
	numeral.add_theme_font_size_override("font_size", 14)
	numeral.add_theme_color_override("font_color",
		Color(0.10, 0.08, 0.05) if done else Color(1, 1, 1, 0.65))
	numeral.set_anchors_preset(Control.PRESET_FULL_RECT)
	numeral.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	numeral.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	medal.add_child(numeral)
	h.add_child(medal)

	# Name + current-tier description + progress
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(vb)

	var nm := Label.new()
	nm.text = g["name"] + ((" " + GameState.TIER_NUMERALS[shown]) if tiers.size() > 1 and not done else "")
	nm.add_theme_font_size_override("font_size", 17)
	nm.add_theme_color_override("font_color", Color(1, 1, 1, 0.95) if done else Color(1, 1, 1, 0.75))
	vb.add_child(nm)

	var ds := Label.new()
	ds.text = "ALL TIERS COMPLETE" if done else _ach_desc(g, target)
	ds.add_theme_font_size_override("font_size", 12)
	ds.add_theme_color_override("font_color",
		Color(0.95, 0.78, 0.20, 0.85) if done else Color(1, 1, 1, 0.40))
	vb.add_child(ds)

	if not done:
		var ph := HBoxContainer.new()
		ph.add_theme_constant_override("separation", 8)
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(ph)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = target
		bar.value = mini(v, target)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 10)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bbg := StyleBoxFlat.new()
		bbg.bg_color = Color(0, 0, 0, 0.35)
		bbg.set_corner_radius_all(5)
		var bfg := StyleBoxFlat.new()
		bfg.bg_color = Color(0.95, 0.78, 0.20)
		bfg.set_corner_radius_all(5)
		bar.add_theme_stylebox_override("background", bbg)
		bar.add_theme_stylebox_override("fill", bfg)
		ph.add_child(bar)
		var pl := Label.new()
		@warning_ignore("static_called_on_instance")
		pl.text = GameState.fmt(mini(v, target)) + " / " + GameState.fmt(target)
		pl.add_theme_font_size_override("font_size", 11)
		pl.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
		pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ph.add_child(pl)

	# XP chip: current tier's reward, or total earned when complete
	var chip := Label.new()
	var chip_xp : int = tiers[shown][1]
	if done:
		chip_xp = 0
		for tier in tiers:
			chip_xp += tier[1]
	chip.text = "MILESTONE" if chip_xp == 0 else "+" + str(chip_xp) + " XP"
	chip.add_theme_font_size_override("font_size", 13)
	var csb := StyleBoxFlat.new()
	csb.set_corner_radius_all(10)
	csb.content_margin_left = 10; csb.content_margin_right = 10
	csb.content_margin_top = 4;   csb.content_margin_bottom = 4
	if done:
		csb.bg_color = Color(0.95, 0.78, 0.20)
		chip.add_theme_color_override("font_color", Color(0.10, 0.08, 0.05))
	else:
		csb.bg_color = Color(0, 0, 0, 0.30)
		chip.add_theme_color_override("font_color", Color(1, 1, 1, 0.40))
	chip.add_theme_stylebox_override("normal", csb)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(chip)

	return card

# Expanded ladder: one line per tier, coloured by state
func _make_tier_list(g: Dictionary) -> PanelContainer:
	var cur := _ach_current_tier(g)
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.22)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 18; sb.content_margin_right = 14
	sb.content_margin_top = 8;   sb.content_margin_bottom = 8
	box.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	box.add_child(vb)

	for ti in g["tiers"].size():
		var tier : Array = g["tiers"][ti]
		var got : bool = GameState.unlocked.get("%s_%d" % [g["id"], ti], false)
		var row := Label.new()
		var numeral : String = GameState.TIER_NUMERALS[ti] if g["tiers"].size() > 1 else "I"
		var state : String = "DONE" if got else ("NEXT" if ti == cur else "LOCKED")
		var xp_str : String = "MILESTONE" if int(tier[1]) == 0 else "+" + str(tier[1]) + " XP"
		row.text = numeral + "    " + _ach_desc(g, tier[0]) + "    ·    " + xp_str + "    ·    " + state
		row.add_theme_font_size_override("font_size", 12)
		if got:
			row.add_theme_color_override("font_color", Color(0.95, 0.78, 0.20, 0.95))
		elif ti == cur:
			row.add_theme_color_override("font_color", Color(1, 1, 1, 0.80))
		else:
			row.add_theme_color_override("font_color", Color(1, 1, 1, 0.30))
		vb.add_child(row)

	return box

func _fmt_num(n: int) -> String:
	# Group every 3 digits — correct for millions+ (old version only added ONE comma)
	var s := str(absi(n))
	var out := ""
	var cnt := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if n < 0 else out

func _open_achievements() -> void:
	_populate_achievements()
	ach_box.visible = true
	ach_box.scale = Vector2(0.85, 0.85)
	ach_box.pivot_offset = Vector2(185, 280)
	var t := create_tween()
	t.tween_property(ach_box, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ── Biomes gallery ───────────────────────────────────────────────────────────
# The whole gallery is gated until the player reaches this level.
const BIOMES_UNLOCK_LEVEL := 3

# Rarity tiers (mirror GameState.SKIN_UNLOCK). Indices are skin ids; color tints
# the section header so rarity reads at a glance.
const BIOME_TIERS : Array = [
	{"name": "COMMON",    "color": Color(0.72, 0.76, 0.82), "skins": [0, 1, 2, 3, 4]},
	{"name": "RARE",      "color": Color(0.35, 0.66, 0.98), "skins": [5, 6, 7, 8, 10, 13, 18]},
	{"name": "EPIC",      "color": Color(0.74, 0.46, 0.99), "skins": [9, 12, 14, 28, 22, 19, 27, 17, 26, 29]},
	{"name": "LEGENDARY", "color": Color(0.98, 0.79, 0.30), "skins": [16, 20, 11, 25, 24, 23, 21, 15]},
]

func _build_biomes_panel() -> void:
	biome_box = PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.11, 0.14, 0.13)
	psb.set_corner_radius_all(24)
	psb.border_width_bottom = 8
	psb.border_color = Color(0.05, 0.07, 0.06)
	psb.content_margin_left = 18; psb.content_margin_right = 18
	psb.content_margin_top = 16;  psb.content_margin_bottom = 20
	biome_box.add_theme_stylebox_override("panel", psb)
	biome_box.position = Vector2(22, 64)
	biome_box.custom_minimum_size = Vector2(370, 0)
	biome_box.visible = false
	ui.add_child(biome_box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	biome_box.add_child(vbox)

	var title := Label.new()
	title.text = "BIOMES"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Lock / shuffle toggle
	biome_mode_btn = _make_chunky_button(_biome_mode_text(), Color(0.30, 0.80, 0.55), 18)
	biome_mode_btn.custom_minimum_size = Vector2(0, 48)
	biome_mode_btn.pressed.connect(func():
		GameState.set_skin_locked(not GameState.skin_locked)
		_refresh_biome_mode()
		_populate_biomes())
	vbox.add_child(biome_mode_btn)

	biome_hint = Label.new()
	biome_hint.add_theme_font_size_override("font_size", 13)
	biome_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	biome_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	biome_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	biome_hint.custom_minimum_size = Vector2(334, 0)
	vbox.add_child(biome_hint)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(334, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	biome_rows = VBoxContainer.new()
	biome_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	biome_rows.add_theme_constant_override("separation", 10)
	biome_rows.mouse_filter = Control.MOUSE_FILTER_PASS   # drags scroll, taps select
	scroll.add_child(biome_rows)

	var close := _make_chunky_button("CLOSE", Color(0.90, 0.30, 0.40), 18)
	close.custom_minimum_size = Vector2(0, 50)
	close.pressed.connect(func():
		Sfx.play_click()
		biome_box.visible = false)
	vbox.add_child(close)

func _biome_mode_text() -> String:
	return "MODE:  LOCKED" if GameState.skin_locked else "MODE:  SHUFFLE"

func _refresh_biome_mode() -> void:
	biome_mode_btn.text = _biome_mode_text()
	if GameState.skin_locked:
		var idx : int = GameState.picked_skin if GameState.picked_skin >= 0 else 0
		biome_hint.text = "Staying on " + SKIN_NAMES[idx % SKIN_NAMES.size()] + " every game"
	else:
		biome_hint.text = "Rotating your unlocked biomes as you clear rows"

# Rebuilt on open / mode-toggle / selection so highlights stay correct
func _populate_biomes() -> void:
	for child in biome_rows.get_children():
		child.queue_free()
	biome_swatches.clear()
	var current := _menu_skin()
	for tier in BIOME_TIERS:
		var header := Label.new()
		header.text = tier["name"]
		header.add_theme_font_size_override("font_size", 16)
		header.add_theme_color_override("font_color", tier["color"])
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		biome_rows.add_child(header)

		var grid := GridContainer.new()
		grid.columns = 3
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		biome_rows.add_child(grid)
		for idx in tier["skins"]:
			grid.add_child(_make_biome_card(int(idx), current))

func _make_biome_card(idx: int, current: int) -> PanelContainer:
	var unlocked := GameState.is_skin_unlocked(idx)
	var locked   := not unlocked
	var selected := unlocked and idx == current

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(102, 0)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 6; sb.content_margin_right = 6
	sb.content_margin_top = 6;  sb.content_margin_bottom = 8
	if selected:
		sb.bg_color = Color(0.95, 0.78, 0.20, 0.16)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.98, 0.82, 0.30)
	elif locked:
		# Sunken dark look so locked cards read as "off" (no light edge)
		sb.bg_color = Color(0.0, 0.0, 0.0, 0.25)
	else:
		sb.bg_color = Color(1, 1, 1, 0.06)
	card.add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)

	# Live skin preview
	var swatch := Control.new()
	swatch.custom_minimum_size = Vector2(90, 44)
	swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sidx := idx
	var slocked := locked
	var scol : Color = COLORS[idx % COLORS.size()]
	swatch.draw.connect(func():
		var sz := swatch.size
		if slocked:
			# Flat dark plate + padlock — no skin pixels, so no stray light edges
			BlockSkins.rr_fill(swatch, Rect2(1.0, 1.0, sz.x - 2.0, sz.y - 2.0), 6.0, Color(0.10, 0.10, 0.14))
			_draw_padlock(swatch, sz * 0.5, 20.0)
		else:
			var cs : float = sz.y
			var n := maxi(1, int(sz.x / cs))
			var off := (sz.x - cs * float(n)) * 0.5
			for k in n:
				BlockSkins.paint(swatch, sidx,
					Rect2(off + float(k) * cs + 1.0, 0.0, cs - 2.0, cs - 2.0),
					scol, 11 + k * 7))
	col.add_child(swatch)
	biome_swatches.append(swatch)

	var name_lbl := Label.new()
	name_lbl.text = SKIN_NAMES[idx]
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.45) if locked else Color(1, 1, 1, 0.92))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_lbl)

	var status := Label.new()
	status.add_theme_font_size_override("font_size", 10)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not unlocked:
		var hint := GameState.skin_unlock_hint(idx)
		status.text = hint if hint != "" else "LOCKED"
		status.add_theme_color_override("font_color", Color(0.95, 0.75, 0.45, 0.85))
	elif selected:
		status.text = "IN USE"
		status.add_theme_color_override("font_color", Color(0.98, 0.82, 0.30))
	else:
		status.text = "TAP TO USE"
		status.add_theme_color_override("font_color", Color(0.55, 0.85, 0.70, 0.8))
	col.add_child(status)

	var tap_idx := idx
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if GameState.is_skin_unlocked(tap_idx):
				GameState.select_skin(tap_idx)
				Sfx.play_click()
				_refresh_biome_mode()
				_populate_biomes()
			else:
				Sfx.play_tick())
	return card

func _open_biomes() -> void:
	_refresh_biome_mode()
	_populate_biomes()
	biome_box.visible = true
	biome_box.scale = Vector2(0.85, 0.85)
	biome_box.pivot_offset = Vector2(185, 300)
	var t := create_tween()
	t.tween_property(biome_box, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# A small padlock — the universal "locked" mark (no font glyph needed)
func _draw_padlock(ci: CanvasItem, c: Vector2, h: float) -> void:
	var col  := Color(0.96, 0.97, 1.0, 0.96)
	var dark := Color(0.08, 0.08, 0.14, 0.92)
	var bw := h * 0.92
	var bh := h * 0.60
	var body := Rect2(c.x - bw * 0.5, c.y - bh * 0.10, bw, bh)
	ci.draw_arc(Vector2(c.x, body.position.y + 1.0), bw * 0.30, PI, TAU, 18, col, maxf(h * 0.11, 2.0))
	BlockSkins.rr_fill(ci, body, h * 0.14, col)
	ci.draw_circle(Vector2(c.x, body.position.y + bh * 0.45), h * 0.11, dark)

# Padlock badge pinned to the right edge of a (locked) button
func _add_lock_badge(b: Button) -> void:
	var badge := Control.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.position = Vector2(b.size.x - 40.0, b.size.y * 0.5 - 12.0)
	badge.custom_minimum_size = Vector2(24, 24)
	b.add_child(badge)
	badge.draw.connect(func(): _draw_padlock(badge, Vector2(12, 12), 22.0))
	badge.queue_redraw()

# Denied feedback: a quick horizontal wobble + the invalid blip
func _deny_button(b: Button) -> void:
	Sfx.play_invalid()
	var ox := b.position.x
	var t := create_tween()
	t.tween_property(b, "position:x", ox - 7.0, 0.05).set_trans(Tween.TRANS_SINE)
	t.tween_property(b, "position:x", ox + 7.0, 0.05).set_trans(Tween.TRANS_SINE)
	t.tween_property(b, "position:x", ox, 0.06).set_trans(Tween.TRANS_SINE)

# ── Buttons ───────────────────────────────────────────────────────────────────
# ── Leaderboard + friends panel ───────────────────────────────────────────────
func _build_leaderboard_panel() -> void:
	lb_box = PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.12, 0.11, 0.08)
	psb.set_corner_radius_all(24)
	psb.border_width_bottom = 8
	psb.border_color = Color(0.06, 0.05, 0.03)
	psb.content_margin_left = 18; psb.content_margin_right = 18
	psb.content_margin_top = 16;  psb.content_margin_bottom = 20
	lb_box.add_theme_stylebox_override("panel", psb)
	lb_box.position = Vector2(22, 60)
	lb_box.custom_minimum_size = Vector2(370, 0)
	lb_box.visible = false
	ui.add_child(lb_box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	lb_box.add_child(vbox)

	var title := Label.new()
	title.text = "LEADERBOARD"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1, 0.92, 0.6))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Global / Friends tabs
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	vbox.add_child(tabs)
	lb_global_btn = _make_chunky_button("GLOBAL", Color(0.95, 0.75, 0.25), 18)
	lb_global_btn.custom_minimum_size = Vector2(0, 46)
	lb_global_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb_global_btn.pressed.connect(func(): _set_lb_tab("global"))
	tabs.add_child(lb_global_btn)
	lb_friends_btn = _make_chunky_button("FRIENDS", Color(0.30, 0.80, 0.55), 18)
	lb_friends_btn.custom_minimum_size = Vector2(0, 46)
	lb_friends_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb_friends_btn.pressed.connect(func(): _set_lb_tab("friends"))
	tabs.add_child(lb_friends_btn)

	var swipe_hint := Label.new()
	swipe_hint.text = "swipe to switch"
	swipe_hint.add_theme_font_size_override("font_size", 13)
	swipe_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	swipe_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(swipe_hint)

	# Your shareable code + copy
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 6)
	vbox.add_child(code_row)
	var code_lbl := Label.new()
	code_lbl.text = "YOUR CODE:  " + GameState.friend_code
	code_lbl.add_theme_font_size_override("font_size", 15)
	code_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	code_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(code_lbl)
	var copy := _make_chunky_button("COPY", Color(0.40, 0.55, 0.95), 14)
	copy.custom_minimum_size = Vector2(74, 40)
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(GameState.friend_code)
		_flash_lb_status("Code copied!", Color(0.55, 0.85, 1.0)))
	code_row.add_child(copy)

	# Add a friend by their code
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 6)
	vbox.add_child(add_row)
	lb_code_input = LineEdit.new()
	lb_code_input.placeholder_text = "friend's code"
	lb_code_input.max_length = 7
	lb_code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb_code_input.custom_minimum_size = Vector2(0, 42)
	add_row.add_child(lb_code_input)
	var add_btn := _make_chunky_button("ADD", Color(0.30, 0.80, 0.55), 16)
	add_btn.custom_minimum_size = Vector2(74, 42)
	add_btn.pressed.connect(_on_add_friend_pressed)
	add_row.add_child(add_btn)

	lb_status = Label.new()
	lb_status.add_theme_font_size_override("font_size", 14)
	lb_status.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	lb_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lb_status)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(334, 372)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	lb_rows = VBoxContainer.new()
	lb_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb_rows.add_theme_constant_override("separation", 6)
	lb_rows.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(lb_rows)

	var close := _make_chunky_button("CLOSE", Color(0.90, 0.30, 0.40), 18)
	close.custom_minimum_size = Vector2(0, 50)
	close.pressed.connect(func():
		Sfx.play_click()
		lb_box.visible = false)
	vbox.add_child(close)

	# Wire Net responses once (autoload persists; guard against double-connect)
	if not Net.global_board.is_connected(_on_global_board):
		Net.global_board.connect(_on_global_board)
	if not Net.friends_board.is_connected(_on_friends_board):
		Net.friends_board.connect(_on_friends_board)
	if not Net.friend_added.is_connected(_on_friend_added):
		Net.friend_added.connect(_on_friend_added)

func _open_leaderboard() -> void:
	lb_box.visible = true
	lb_box.scale = Vector2(0.85, 0.85)
	lb_box.pivot_offset = Vector2(185, 300)
	var t := create_tween()
	t.tween_property(lb_box, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_set_lb_tab("global")

func _set_lb_tab(tab: String) -> void:
	lb_tab = tab
	lb_global_btn.modulate.a  = 1.0 if tab == "global" else 0.45
	lb_friends_btn.modulate.a = 1.0 if tab == "friends" else 0.45
	for child in lb_rows.get_children():
		child.queue_free()
	if not Net.is_configured():
		lb_status.text = "Leaderboard offline"
		return
	lb_status.text = "Loading…"
	if tab == "global":
		Net.fetch_global(50)
	else:
		Net.fetch_friends(GameState.player_id)

func _on_global_board(rows: Array) -> void:
	_cache_my_rank(rows)   # update the profile pin even when the board isn't open
	if lb_box != null and lb_box.visible and lb_tab == "global":
		_populate_board(rows, false)

# Find the player's own row in the global board and remember their rank so the
# main-menu profile pin reflects it. Works whenever the player is in the fetched
# top-N; full coverage (lower tiers) would need a get_my_rank RPC backend-side.
func _cache_my_rank(rows: Array) -> void:
	for row in rows:
		var nm : String = str(row.get("name", "?"))
		var sc : int    = int(row.get("best_score", 0))
		if nm == GameState.player_name and sc == GameState.best_score:
			GameState.set_global_rank(int(row.get("rank", 0)))
			if is_instance_valid(profile_pin):
				_refresh_profile()
			return

func _on_friends_board(rows: Array) -> void:
	if lb_box != null and lb_box.visible and lb_tab == "friends":
		_populate_board(rows, true)

func _populate_board(rows: Array, is_friends: bool) -> void:
	for child in lb_rows.get_children():
		child.queue_free()
	if rows.is_empty():
		lb_status.text = "No friends yet — add some by code!" if is_friends else "No scores yet"
		return
	lb_status.text = ""
	# Fade the list in so swiping between tabs reads like a page turn
	lb_rows.modulate.a = 0.0
	create_tween().tween_property(lb_rows, "modulate:a", 1.0, 0.18)
	for row in rows:
		var rank : int    = int(row.get("rank", 0))
		var nm   : String = str(row.get("name", "?"))
		var sc   : int    = int(row.get("best_score", 0))
		var mine : bool
		if is_friends:
			mine = bool(row.get("is_me", false))
		else:
			mine = nm == GameState.player_name and sc == GameState.best_score
		lb_rows.add_child(_make_board_row(rank, nm, sc, mine, _row_tier(row, is_friends, mine)))

# Pin tier for a board row. Global board: the row's rank IS the global rank. Friends
# board: use a global_rank field if the backend supplies one, else show only YOUR own
# row (we know your rank) — a friend's local rank isn't their global standing.
func _row_tier(row: Dictionary, is_friends: bool, mine: bool) -> int:
	if not is_friends:
		return _rank_tier(int(row.get("rank", 0)))
	var gr := int(row.get("global_rank", 0))
	if gr > 0:
		return _rank_tier(gr)
	if mine:
		return _rank_tier(GameState.my_global_rank)
	return 0

func _make_board_row(rank: int, nm: String, score: int, mine: bool, tier: int) -> PanelContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 10; sb.content_margin_right = 10
	sb.content_margin_top = 7;   sb.content_margin_bottom = 7
	if mine:
		sb.bg_color = Color(0.95, 0.78, 0.20, 0.20)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.98, 0.82, 0.30)
	else:
		sb.bg_color = Color(1, 1, 1, 0.05)
	card.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	# Rank-tier pin (kept as an empty slot when none, so columns stay aligned)
	row.add_child(_make_rank_pin(tier))

	var rank_lbl := Label.new()
	rank_lbl.text = "#" + str(rank)
	rank_lbl.add_theme_font_size_override("font_size", 18)
	var rcol := Color(1, 1, 1, 0.8)
	if rank == 1:   rcol = Color(1.00, 0.84, 0.25)
	elif rank == 2: rcol = Color(0.80, 0.84, 0.90)
	elif rank == 3: rcol = Color(0.90, 0.62, 0.36)
	rank_lbl.add_theme_color_override("font_color", rcol)
	rank_lbl.custom_minimum_size = Vector2(48, 0)
	row.add_child(rank_lbl)

	var name_lbl := Label.new()
	name_lbl.text = nm
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)

	var score_lbl := Label.new()
	score_lbl.text = _fmt_num(score)
	score_lbl.add_theme_font_size_override("font_size", 18)
	score_lbl.add_theme_color_override("font_color", Color(1, 0.92, 0.6))
	row.add_child(score_lbl)
	return card

# ── Rank pins: a medallion ladder by GLOBAL rank ─────────────────────────────
# 0 = none. Six tiers, ascending prestige:
#   1 = 101-1000 (slate + star outline)   2 = 11-100 (teal + filled star)
#   3 = 4-10 (bronze + gem)               4 = rank 3 (silver + gem + glow)
#   5 = rank 2 (gold + gem + glow)        6 = rank 1 (royal purple + big gem + glow + sparkles)
func _rank_tier(rank: int) -> int:
	if rank <= 0:    return 0
	if rank == 1:    return 6
	if rank == 2:    return 5
	if rank == 3:    return 4
	if rank <= 10:   return 3
	if rank <= 100:  return 2
	if rank <= 1000: return 1
	return 0

func _make_rank_pin(tier: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(32, 32)   # fixed slot keeps the rank column aligned
	if tier > 0:
		c.draw.connect(func(): _draw_pin(c, Vector2(16, 20), 11.0, tier))
	return c

func _draw_pin(canvas: Control, center: Vector2, r: float, tier: int) -> void:
	var base : Color
	var rim  : Color
	match tier:
		1: base = Color(0.44, 0.47, 0.56); rim = Color(0.22, 0.24, 0.30)   # slate (101-1000)
		2: base = Color(0.18, 0.56, 0.64); rim = Color(0.07, 0.30, 0.36)   # teal (11-100)
		3: base = Color(0.82, 0.52, 0.30); rim = Color(0.45, 0.26, 0.12)   # bronze (4-10)
		4: base = Color(0.80, 0.84, 0.92); rim = Color(0.45, 0.50, 0.58)   # silver (rank 3)
		5: base = Color(1.00, 0.82, 0.28); rim = Color(0.66, 0.46, 0.08)   # gold (rank 2)
		_: base = Color(0.50, 0.26, 0.70); rim = Color(0.98, 0.78, 0.24)   # royal purple (rank 1)

	# Glow ring — podium only (rank 1 gets a brighter gold double-glow)
	match tier:
		6:
			canvas.draw_circle(center, r * 1.55, Color(1.00, 0.85, 0.30, 0.18))
			canvas.draw_circle(center, r * 1.30, Color(1.00, 0.90, 0.45, 0.18))
		5:
			canvas.draw_circle(center, r * 1.40, Color(1.00, 0.85, 0.30, 0.16))
		4:
			canvas.draw_circle(center, r * 1.38, Color(0.85, 0.90, 1.00, 0.15))

	# Medallion: chunky rim, body, subtle inner accent ring
	canvas.draw_circle(center, r, rim)
	canvas.draw_circle(center, r * 0.80, base)
	canvas.draw_arc(center, r * 0.80, 0.0, TAU, 28, base.lightened(0.30), 1.5, true)

	# Emblem: stars for the range tiers, gems for the elite/podium tiers
	match tier:
		1: _draw_pin_star(canvas, center, r * 0.52, Color(1, 0.96, 0.86), false)   # outline star
		2: _draw_pin_star(canvas, center, r * 0.54, Color(1, 1, 1), true)          # filled star
		6: _draw_pin_gem(canvas, center, r * 0.66)                                  # rank 1: big gem
		_: _draw_pin_gem(canvas, center, r * 0.52)                                  # 4-10 / rank 3 / rank 2

	# Sticker gloss
	canvas.draw_circle(center + Vector2(-r * 0.32, -r * 0.36), r * 0.16, Color(1, 1, 1, 0.55))

	# Podium sparkles
	match tier:
		6:
			_draw_sparkle(canvas, center + Vector2(r * 0.78, -r * 0.74), r * 0.26)
			_draw_sparkle(canvas, center + Vector2(-r * 0.82, r * 0.30), r * 0.16)
		5:
			_draw_sparkle(canvas, center + Vector2(r * 0.80, -r * 0.72), r * 0.20)
		4:
			_draw_sparkle(canvas, center + Vector2(r * 0.80, -r * 0.72), r * 0.18)

func _draw_pin_star(canvas: Control, center: Vector2, r_out: float, col: Color, filled: bool) -> void:
	var pts := _bubbly_star_points(center, r_out, r_out * 0.5, 0.4)
	if filled:
		canvas.draw_colored_polygon(pts, col)
	var outline := pts.duplicate()
	outline.append(pts[0])
	canvas.draw_polyline(outline, col.darkened(0.35) if filled else col, 1.5, true)

func _draw_pin_gem(canvas: Control, center: Vector2, s: float) -> void:
	var top := center + Vector2(0, -s)
	var rgt := center + Vector2(s * 0.78, 0)
	var bot := center + Vector2(0, s)
	var lft := center + Vector2(-s * 0.78, 0)
	var pts := PackedVector2Array([top, rgt, bot, lft])
	canvas.draw_colored_polygon(pts, Color(0.50, 0.88, 1.00))
	canvas.draw_colored_polygon(PackedVector2Array([top, rgt, center, lft]), Color(0.80, 0.97, 1.00))
	var ol := pts.duplicate()
	ol.append(pts[0])
	canvas.draw_polyline(ol, Color(0.18, 0.44, 0.64), 1.4, true)

func _draw_sparkle(canvas: Control, pos: Vector2, s: float) -> void:
	var pts := PackedVector2Array([
		pos + Vector2(0, -s),         pos + Vector2(s * 0.22, -s * 0.22),
		pos + Vector2(s, 0),          pos + Vector2(s * 0.22, s * 0.22),
		pos + Vector2(0, s),          pos + Vector2(-s * 0.22, s * 0.22),
		pos + Vector2(-s, 0),         pos + Vector2(-s * 0.22, -s * 0.22),
	])
	canvas.draw_colored_polygon(pts, Color(1, 1, 1, 0.9))

func _on_add_friend_pressed() -> void:
	var code := lb_code_input.text.strip_edges()
	if code.length() < 4:
		_flash_lb_status("Enter a friend code", Color(1.0, 0.6, 0.4))
		return
	if not Net.is_configured():
		_flash_lb_status("Leaderboard offline", Color(1.0, 0.6, 0.4))
		return
	Sfx.play_click()
	lb_status.text = "Adding…"
	Net.add_friend(GameState.player_id, code)

func _on_friend_added(friend_name: String) -> void:
	if lb_box == null or not lb_box.visible:
		return
	if friend_name == "":
		_flash_lb_status("No player with that code", Color(1.0, 0.5, 0.4))
		return
	lb_code_input.clear()
	_flash_lb_status("Added " + friend_name + "!", Color(0.55, 0.9, 0.55))
	if lb_tab == "friends":
		Net.fetch_friends(GameState.player_id)

func _flash_lb_status(msg: String, col: Color) -> void:
	lb_status.text = msg
	lb_status.add_theme_color_override("font_color", col)
	var t := create_tween()
	t.tween_interval(1.6)
	t.tween_callback(func():
		lb_status.add_theme_color_override("font_color", Color(1, 1, 1, 0.6)))

func _make_chunky_button(label_text: String, fill: Color, font_size: int = 24) -> Button:
	var b := Button.new()
	b.text = label_text
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(20)
	sb.border_width_bottom = 7
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

func _build_buttons() -> void:
	var has_run := GameState.has_run_save()
	var fade_in : Array = []
	var primary : Button

	if has_run:
		var cont := _make_chunky_button("CONTINUE", Color(0.95, 0.75, 0.15), 28)
		cont.size = Vector2(280, 72)
		cont.position = Vector2(67, 430)
		cont.pivot_offset = cont.size * 0.5
		ui.add_child(cont)
		cont.pressed.connect(_on_continue_pressed.bind(cont))
		fade_in.append(cont)
		primary = cont

		var play := _make_chunky_button("NEW GAME", Color(0.20, 0.85, 0.45), 22)
		play.size = Vector2(280, 58)
		play.position = Vector2(67, 516)
		play.pivot_offset = play.size * 0.5
		ui.add_child(play)
		play.pressed.connect(_on_play_pressed.bind(play))
		fade_in.append(play)
	else:
		var play := _make_chunky_button("PLAY", Color(0.20, 0.85, 0.45), 34)
		play.size = Vector2(280, 78)
		play.position = Vector2(67, 430)
		play.pivot_offset = play.size * 0.5
		ui.add_child(play)
		play.pressed.connect(_on_play_pressed.bind(play))
		fade_in.append(play)
		primary = play

	var ach := _make_chunky_button("ACHIEVEMENTS", Color(0.95, 0.55, 0.25), 22)
	ach.size = Vector2(280, 58)
	ach.position = Vector2(67, 588 if has_run else 526)
	ach.pivot_offset = ach.size * 0.5
	ui.add_child(ach)
	ach.pressed.connect(func():
		Sfx.play_click()
		_open_achievements())
	fade_in.append(ach)

	var leaderboard := _make_chunky_button("LEADERBOARD", Color(0.95, 0.75, 0.25), 22)
	leaderboard.size = Vector2(280, 58)
	leaderboard.position = Vector2(67, 660 if has_run else 598)
	leaderboard.pivot_offset = leaderboard.size * 0.5
	ui.add_child(leaderboard)
	leaderboard.pressed.connect(func():
		Sfx.play_click()
		_open_leaderboard())
	fade_in.append(leaderboard)

	var biomes_ok := GameState.get_level() >= BIOMES_UNLOCK_LEVEL
	var biomes := _make_chunky_button(
		"BIOMES" if biomes_ok else "BIOMES   LV " + str(BIOMES_UNLOCK_LEVEL),
		Color(0.30, 0.80, 0.55) if biomes_ok else Color(0.34, 0.34, 0.42), 22)
	biomes.size = Vector2(280, 58)
	biomes.position = Vector2(67, 732 if has_run else 670)
	biomes.pivot_offset = biomes.size * 0.5
	ui.add_child(biomes)
	if biomes_ok:
		biomes.pressed.connect(func():
			Sfx.play_click()
			_open_biomes())
	else:
		# Locked: padlock badge + a denied wobble instead of opening
		_add_lock_badge(biomes)
		biomes.pressed.connect(_deny_button.bind(biomes))
	fade_in.append(biomes)

	var settings := _make_chunky_button("SETTINGS", Color(0.20, 0.75, 0.95), 22)
	settings.size = Vector2(280, 58)
	settings.position = Vector2(67, 804 if has_run else 742)
	settings.pivot_offset = settings.size * 0.5
	ui.add_child(settings)
	settings.pressed.connect(func():
		Sfx.play_click()
		_open_settings())
	fade_in.append(settings)

	# Fade buttons in after the logo lands
	for btn in fade_in:
		btn.modulate.a = 0.0
		var t := create_tween()
		t.tween_interval(0.85)
		t.tween_property(btn, "modulate:a", 1.0, 0.35)

	# Idle pulse on the primary button so it invites a tap
	play_pulse = create_tween().set_loops()
	play_pulse.tween_interval(1.2)
	play_pulse.tween_property(primary, "scale", Vector2(1.05, 1.05), 0.45).set_trans(Tween.TRANS_SINE)
	play_pulse.tween_property(primary, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_SINE)

func _on_play_pressed(play: Button) -> void:
	# A saved run exists → confirm before wiping it
	if GameState.has_run_save():
		_confirm_new_game(play)
		return
	GameState.has_save = false
	GameState.clear_run()
	_launch(play)

func _confirm_new_game(play: Button) -> void:
	Sfx.play_click()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.size = Vector2(414, 896)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(dim)

	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.11, 0.19, 0.99)
	sb.set_corner_radius_all(20)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.content_margin_left = 22; sb.content_margin_right = 22
	sb.content_margin_top = 22;  sb.content_margin_bottom = 22
	box.add_theme_stylebox_override("panel", sb)
	box.custom_minimum_size = Vector2(322, 0)
	box.position = Vector2(46, 330)
	dim.add_child(box)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	box.add_child(vb)

	var title := Label.new()
	title.text = "START NEW GAME?"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	var msg := Label.new()
	msg.text = "Your saved run will be lost."
	msg.add_theme_font_size_override("font_size", 17)
	msg.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(msg)

	var yes := _make_chunky_button("NEW GAME", Color(0.90, 0.35, 0.35), 22)
	yes.custom_minimum_size = Vector2(278, 56)
	vb.add_child(yes)
	var no := _make_chunky_button("KEEP PLAYING", Color(0.20, 0.75, 0.95), 22)
	no.custom_minimum_size = Vector2(278, 56)
	vb.add_child(no)

	box.modulate.a = 0.0
	box.scale = Vector2(0.9, 0.9)
	box.pivot_offset = Vector2(161, 120)
	var t := create_tween()
	t.tween_property(box, "modulate:a", 1.0, 0.15)
	t.parallel().tween_property(box, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	yes.pressed.connect(func():
		GameState.has_save = false
		GameState.clear_run()
		_launch(play))
	no.pressed.connect(func():
		Sfx.play_click()
		dim.queue_free())

func _on_continue_pressed(cont: Button) -> void:
	if not GameState.load_run_from_disk():
		# Run file unreadable — fall back to a fresh game
		GameState.has_save = false
		GameState.clear_run()
	_launch(cont)

func _launch(btn: Button) -> void:
	Sfx.play_click()
	if play_pulse:
		play_pulse.kill()
	var t := create_tween()
	t.tween_property(btn, "scale", Vector2(0.90, 0.90), 0.08)
	t.tween_property(btn, "scale", Vector2(1.08, 1.08), 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(func(): get_tree().change_scene_to_file("res://scenes/Game.tscn"))

# ── Settings panel ────────────────────────────────────────────────────────────
func _build_settings_panel() -> void:
	settings_box = PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.12, 0.10, 0.18)
	psb.set_corner_radius_all(24)
	psb.border_width_bottom = 8
	psb.border_color = Color(0.06, 0.05, 0.10)
	psb.content_margin_left = 28; psb.content_margin_right = 28
	psb.content_margin_top = 24;  psb.content_margin_bottom = 28
	settings_box.add_theme_stylebox_override("panel", psb)
	settings_box.position = Vector2(57, 280)
	settings_box.custom_minimum_size = Vector2(300, 0)
	settings_box.visible = false
	ui.add_child(settings_box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	settings_box.add_child(vbox)

	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var snd := _make_chunky_button(_sound_text(), Color(0.20, 0.75, 0.95), 20)
	snd.custom_minimum_size = Vector2(0, 56)
	snd.pressed.connect(func():
		GameState.set_sound(not GameState.sound_on)
		snd.text = _sound_text()
		Sfx.play_click())
	vbox.add_child(snd)

	var mus := _make_chunky_button(_music_text(), Color(0.65, 0.30, 0.95), 20)
	mus.custom_minimum_size = Vector2(0, 56)
	mus.pressed.connect(func():
		GameState.set_music(not GameState.music_on)
		Sfx.update_music()
		mus.text = _music_text()
		Sfx.play_click())
	vbox.add_child(mus)

	var hap := _make_chunky_button(_haptics_text(), Color(0.95, 0.75, 0.15), 20)
	hap.custom_minimum_size = Vector2(0, 56)
	hap.pressed.connect(func():
		GameState.set_haptics(not GameState.haptics_on)
		hap.text = _haptics_text()
		if GameState.haptics_on:
			Input.vibrate_handheld(30)
		Sfx.play_click())
	vbox.add_child(hap)

	var rename_btn := _make_chunky_button("CHANGE NAME", Color(0.30, 0.80, 0.55), 20)
	rename_btn.custom_minimum_size = Vector2(0, 56)
	rename_btn.pressed.connect(func(): _on_change_name_pressed(rename_btn))
	vbox.add_child(rename_btn)

	var account := _make_chunky_button("ACCOUNT", Color(0.40, 0.55, 0.95), 20)
	account.custom_minimum_size = Vector2(0, 56)
	account.pressed.connect(func():
		Sfx.play_click()
		settings_box.visible = false
		_open_account())
	vbox.add_child(account)

	var close := _make_chunky_button("CLOSE", Color(0.90, 0.30, 0.40), 20)
	close.custom_minimum_size = Vector2(0, 56)
	close.pressed.connect(func():
		Sfx.play_click()
		settings_box.visible = false)
	vbox.add_child(close)

	var ver := Label.new()
	ver.text = "STAX  v" + str(ProjectSettings.get_setting("application/config/version", "1.1.0"))
	ver.add_theme_font_size_override("font_size", 13)
	ver.add_theme_color_override("font_color", Color(1, 1, 1, 0.30))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(ver)

func _sound_text() -> String:
	return "SOUND: ON" if GameState.sound_on else "SOUND: OFF"

func _music_text() -> String:
	return "MUSIC: ON" if GameState.music_on else "MUSIC: OFF"

func _haptics_text() -> String:
	return "HAPTICS: ON" if GameState.haptics_on else "HAPTICS: OFF"

# Watch a rewarded ad, then open the name editor. Repeatable — each rename = one ad.
func _on_change_name_pressed(btn: Button) -> void:
	Sfx.play_click()
	if not Ads.can_offer_rewarded():
		_flash_btn(btn, "NO AD AVAILABLE", "CHANGE NAME")
		return
	btn.disabled = true
	Ads.show_rewarded(func(earned: bool):
		btn.disabled = false
		if earned:
			settings_box.visible = false
			_open_name_change()
		else:
			_flash_btn(btn, "AD NOT FINISHED", "CHANGE NAME"))

func _flash_btn(btn: Button, msg: String, restore: String) -> void:
	btn.text = msg
	var t := create_tween()
	t.tween_interval(1.6)
	t.tween_callback(func():
		if is_instance_valid(btn):
			btn.text = restore)

func _open_name_change() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.70)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(dim)

	var panel := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.13, 0.11, 0.20)
	psb.set_corner_radius_all(24)
	psb.border_width_bottom = 8
	psb.border_color = Color(0.06, 0.05, 0.10)
	psb.content_margin_left = 28; psb.content_margin_right = 28
	psb.content_margin_top = 24;  psb.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", psb)
	panel.position = Vector2(47, 300)
	panel.custom_minimum_size = Vector2(320, 0)
	ui.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "NEW NAME"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var input := LineEdit.new()
	input.max_length = 12
	input.text = GameState.player_name
	input.placeholder_text = "PLAYER"
	input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	input.add_theme_font_size_override("font_size", 22)
	input.custom_minimum_size = Vector2(0, 52)
	vbox.add_child(input)

	var save_btn := _make_chunky_button("SAVE", Color(0.20, 0.85, 0.45), 22)
	save_btn.custom_minimum_size = Vector2(0, 56)
	vbox.add_child(save_btn)

	var cancel := _make_chunky_button("CANCEL", Color(0.90, 0.30, 0.40), 18)
	cancel.custom_minimum_size = Vector2(0, 48)
	vbox.add_child(cancel)

	var close_editor := func():
		dim.queue_free()
		panel.queue_free()

	var confirm := func():
		var n := input.text.strip_edges()
		if not n.is_empty():
			GameState.set_player_name(n)   # persists + _sync_online() upserts the leaderboard row
			_refresh_profile()
		Sfx.play_click()
		close_editor.call()
	save_btn.pressed.connect(confirm)
	input.text_submitted.connect(func(_t): confirm.call())
	cancel.pressed.connect(func():
		Sfx.play_click()
		close_editor.call())
	input.grab_focus()

# ── Account / cloud sign-in ──────────────────────────────────────────────────
var account_overlay : Control
var account_status  : Label

func _open_account() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.70)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(dim)
	account_overlay = dim

	var panel := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.13, 0.11, 0.20)
	psb.set_corner_radius_all(24)
	psb.border_width_bottom = 8
	psb.border_color = Color(0.06, 0.05, 0.10)
	psb.content_margin_left = 24; psb.content_margin_right = 24
	psb.content_margin_top = 22;  psb.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", psb)
	panel.position = Vector2(37, 230)
	panel.custom_minimum_size = Vector2(340, 0)
	dim.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "ACCOUNT"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1, 0.92, 0.6))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var body := Label.new()
	body.text = "Sign in to back up your progress and keep it on any device. You can keep playing without it."
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_color_override("font_color", Color(1, 1, 1, 0.80))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(296, 0)
	vbox.add_child(body)

	account_status = Label.new()
	account_status.add_theme_font_size_override("font_size", 14)
	account_status.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	account_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(account_status)

	if Auth.is_signed_in():
		account_status.text = "Signed in (" + GameState.auth_provider + ") — backed up"
		account_status.add_theme_color_override("font_color", Color(0.55, 0.9, 0.55))
		var out := _make_chunky_button("SIGN OUT", Color(0.90, 0.30, 0.40), 18)
		out.custom_minimum_size = Vector2(0, 50)
		out.pressed.connect(func():
			Sfx.play_click()
			Auth.sign_out())
		vbox.add_child(out)
	else:
		var apple := _make_chunky_button("SIGN IN WITH APPLE", Color(0.92, 0.92, 0.96), 18)
		apple.custom_minimum_size = Vector2(0, 54)
		apple.add_theme_color_override("font_color", Color(0.08, 0.07, 0.10))
		apple.pressed.connect(func(): _start_sign_in("apple"))
		vbox.add_child(apple)

		var google := _make_chunky_button("SIGN IN WITH GOOGLE", Color(0.26, 0.52, 0.96), 18)
		google.custom_minimum_size = Vector2(0, 54)
		google.pressed.connect(func(): _start_sign_in("google"))
		vbox.add_child(google)

	var close := _make_chunky_button("CLOSE", Color(0.55, 0.45, 0.75), 18)
	close.custom_minimum_size = Vector2(0, 50)
	close.pressed.connect(func():
		Sfx.play_click()
		_close_account())
	vbox.add_child(close)

func _start_sign_in(provider: String) -> void:
	Sfx.play_click()
	account_status.text = "Signing in…"
	account_status.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	Auth.begin_sign_in(provider)

func _close_account() -> void:
	if account_overlay != null and is_instance_valid(account_overlay):
		account_overlay.queue_free()
	account_overlay = null
	account_status = null

func _on_auth_signed_in(restored: bool) -> void:
	if is_instance_valid(account_status):
		account_status.text = "Progress restored!" if restored else "Signed in — progress backed up!"
		account_status.add_theme_color_override("font_color", Color(0.55, 0.9, 0.55))
	if is_instance_valid(profile_name):
		_refresh_profile()
	if Net.is_configured():
		Net.fetch_global(50)   # refresh rank/badge under the (now durable) id
	var t := create_tween()
	t.tween_interval(1.4)
	t.tween_callback(_close_account)

func _on_auth_failed(reason: String) -> void:
	if is_instance_valid(account_status):
		account_status.text = reason
		account_status.add_theme_color_override("font_color", Color(1, 0.6, 0.4))

func _on_auth_signed_out() -> void:
	if is_instance_valid(account_status):
		account_status.text = "Signed out"
		account_status.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	if is_instance_valid(profile_name):
		_refresh_profile()

func _open_settings() -> void:
	settings_box.visible = true
	settings_box.scale = Vector2(0.85, 0.85)
	settings_box.pivot_offset = Vector2(150, 130)
	var t := create_tween()
	t.tween_property(settings_box, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

