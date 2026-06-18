extends Node2D

const COLORS: Array = [
	Color(0.32, 0.80, 0.97),
	Color(1.00, 0.63, 0.28),
	Color(0.95, 0.36, 0.68),
	Color(0.33, 0.90, 0.55),
	Color(0.73, 0.43, 0.97),
	Color(0.97, 0.88, 0.32),
]
# Background follows the current skin's theme, dimmed for the mood

@onready var score_label : Label = $UI/FinalScore
@onready var best_label  : Label = $UI/BestScore
@onready var over_label  : Label = $UI/GameOverLabel
@onready var ad_button   : Button = $UI/WatchAdButton
@onready var retry_button: Button = $UI/RetryButton
@onready var menu_button : Button = $UI/MenuButton
@onready var ui          : CanvasLayer = $UI

var orbs         : Array = []
var fallers      : Array = []
var faller_layer : Node2D

# Ad button mode: "revive" (first death) or "double_xp" (after a revive's spent).
# Only ever one ad offer on screen at a time.
var ad_mode      : String = ""
var _dx_claimed  : bool   = false

func _ready() -> void:
	for _i in 8:
		orbs.append({
			"pos":    Vector2(randf() * 414.0, randf() * 896.0),
			"vel":    Vector2((randf() - 0.5) * 16.0, (randf() - 0.5) * 16.0),
			"radius": randf_range(60.0, 130.0),
			"color":  Color(0.9, 0.3, 0.5, randf_range(0.03, 0.07)),
		})
	for _i in 8:
		fallers.append({
			"pos":   Vector2(randf() * 414.0, randf() * 896.0),
			"spd":   randf_range(18.0, 40.0),
			"rot":   randf() * TAU,
			"rspd":  randf_range(-0.6, 0.6),
			"cs":    randf_range(10.0, 15.0),
			"shape": BlockSkins.DEMO_SHAPES[randi() % BlockSkins.DEMO_SHAPES.size()],
			"seed":  randi() % 97,
			"color": COLORS[randi() % COLORS.size()],
		})

	faller_layer = Node2D.new()
	faller_layer.modulate = Color(1, 1, 1, 0.40)
	add_child(faller_layer)
	faller_layer.draw.connect(_draw_fallers)

	_style_buttons()

	# GAME OVER drops in with a bounce
	var over_pos := over_label.position
	over_label.position = over_pos - Vector2(0, 260)
	over_label.pivot_offset = over_label.size * 0.5
	var ot := create_tween()
	ot.tween_property(over_label, "position", over_pos, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	score_label.text = "0"
	score_label.pivot_offset = score_label.size * 0.5

	var is_new_best := GameState.best_score > 0 and GameState.last_score >= GameState.best_score
	if GameState.best_score > 0:
		if is_new_best:
			best_label.text = "★  NEW BEST!  ★"
			best_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.15, 1.0))
		else:
			best_label.text = "BEST  " + str(GameState.best_score)

	# Score count-up with pulse ticks
	var target : int = GameState.last_score
	var tween  := create_tween()
	tween.tween_interval(0.35)
	tween.tween_method(_count_tick, 0.0, float(target), clampf(target * 0.01, 0.1, 1.2))
	tween.tween_callback(func():
		var pt := create_tween()
		pt.tween_property(score_label, "scale", Vector2(1.25, 1.25), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pt.tween_property(score_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
		if is_new_best:
			Sfx.play_best()
			_start_best_shimmer())

	_build_stats_card()
	_build_xp_card()
	_build_leaderboard()
	Sfx.update_music()

	# Achievements earned this run (games-played milestones) toast in
	for i in GameState.pending_toasts.size():
		_show_achievement_toast(GameState.pending_toasts[i], 0.9 + float(i) * 1.1)
	GameState.pending_toasts = []

	# Ad offer: first death → revive; once the revive's been spent, the next
	# death offers a single "double your XP" ad instead. Never two on one screen.
	if not Ads.can_offer_rewarded():
		_hide_ad_button()
	elif not GameState.revive_used:
		ad_mode = "revive"
		ad_button.text = "WATCH AD TO CONTINUE"
	elif GameState.last_xp_gain > 0:
		ad_mode = "double_xp"
		ad_button.text = "WATCH AD: 2× XP"
	else:
		_hide_ad_button()   # revive used + nothing to double → no offer

	# Interstitials disabled — rewarded ads only.

func _hide_ad_button() -> void:
	ad_button.visible = false
	retry_button.position.y -= 82.0
	menu_button.position.y  -= 82.0

# ── Stats card: LINES / BEST STREAK / BOARD CLEARS as columns ────────────────
func _card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.07, 0.13, 0.90)   # near-solid dark so the gold rim pops
	sb.set_corner_radius_all(18)
	sb.corner_detail = 8
	# Bright gold stroke — ties the card to the XP bar and LV chip
	sb.set_border_width_all(2)
	sb.border_color = Color(0.95, 0.78, 0.20, 0.95)
	# Soft gold halo around the whole frame (even glow, no offset)
	sb.shadow_color = Color(0.95, 0.78, 0.20, 0.22)
	sb.shadow_size = 9
	sb.shadow_offset = Vector2.ZERO
	return sb

func _build_stats_card() -> void:
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", _card_style())
	card.position = Vector2(37, 326)
	card.size = Vector2(340, 62)
	card.modulate.a = 0.0
	ui.add_child(card)

	var mult := 1.0
	if GameState.save_max_combo > 1:
		mult = minf(1.0 + 0.25 * float(GameState.save_max_combo - 1), 4.0)
	var mult_s := String.num(mult, 2)
	if mult_s.contains("."):
		mult_s = mult_s.rstrip("0").rstrip(".")

	var stats : Array = [
		[str(GameState.save_lines_cleared), "LINES"],
		["×" + mult_s, "BEST STREAK"],
		[str(GameState.save_board_clears), "BOARD CLEARS"],
	]
	for i in stats.size():
		var v := Label.new()
		v.text = stats[i][0]
		v.add_theme_font_size_override("font_size", 22)
		v.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		v.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.09, 0.85))
		v.add_theme_constant_override("outline_size", 5)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.size = Vector2(113, 30)
		v.position = Vector2(float(i) * 113.0, 6)
		card.add_child(v)
		var c := Label.new()
		c.text = stats[i][1]
		c.add_theme_font_size_override("font_size", 10)
		c.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.size = Vector2(113, 16)
		c.position = Vector2(float(i) * 113.0, 38)
		card.add_child(c)

	var t := create_tween()
	t.tween_interval(0.5)
	t.tween_property(card, "modulate:a", 1.0, 0.35)

# ── XP card: bar animates from pre-run progress, pulsing on level-ups ────────
var xp_level_label : Label
var xp_gain_label  : Label
var xp_count_label : Label
var xp_fill        : Panel
var xp_gloss       : Panel
var shown_level    : int = 1

const XP_BAR_W := 306.0

func _build_xp_card() -> void:
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", _card_style())
	card.position = Vector2(37, 398)
	card.size = Vector2(340, 80)
	card.modulate.a = 0.0
	ui.add_child(card)

	xp_level_label = Label.new()
	xp_level_label.add_theme_font_size_override("font_size", 19)
	xp_level_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	xp_level_label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.09, 0.85))
	xp_level_label.add_theme_constant_override("outline_size", 5)
	xp_level_label.position = Vector2(17, 6)
	xp_level_label.size = Vector2(160, 28)
	xp_level_label.pivot_offset = Vector2(40, 14)
	card.add_child(xp_level_label)

	xp_gain_label = Label.new()
	xp_gain_label.text = "+" + str(GameState.last_xp_gain) + " XP"
	xp_gain_label.add_theme_font_size_override("font_size", 17)
	xp_gain_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.20))
	xp_gain_label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.09, 0.85))
	xp_gain_label.add_theme_constant_override("outline_size", 4)
	xp_gain_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	xp_gain_label.position = Vector2(163, 7)
	xp_gain_label.size = Vector2(160, 28)
	card.add_child(xp_gain_label)

	var track := Panel.new()
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0, 0, 0, 0.40)
	tsb.set_corner_radius_all(7)
	track.add_theme_stylebox_override("panel", tsb)
	track.position = Vector2(17, 42)
	track.size = Vector2(XP_BAR_W, 14)
	card.add_child(track)

	xp_fill = Panel.new()
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.95, 0.78, 0.20)
	fsb.set_corner_radius_all(7)
	xp_fill.add_theme_stylebox_override("panel", fsb)
	xp_fill.position = Vector2(17, 42)
	xp_fill.size = Vector2(0, 14)
	card.add_child(xp_fill)

	# Glossy highlight stripe along the top of the fill — tracks its animated width
	xp_gloss = Panel.new()
	var gsb := StyleBoxFlat.new()
	gsb.bg_color = Color(1, 1, 1, 0.30)
	gsb.set_corner_radius_all(4)
	xp_gloss.add_theme_stylebox_override("panel", gsb)
	xp_gloss.position = Vector2(20, 45)
	xp_gloss.size = Vector2(0, 4)
	card.add_child(xp_gloss)

	xp_count_label = Label.new()
	xp_count_label.add_theme_font_size_override("font_size", 11)
	xp_count_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.50))
	xp_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_count_label.position = Vector2(17, 58)
	xp_count_label.size = Vector2(XP_BAR_W, 16)
	card.add_child(xp_count_label)

	# Start the display at the PRE-run XP, then animate up to the new total
	var xp0 : int = GameState.last_xp_before
	var xp1 : int = GameState.player_xp
	@warning_ignore("static_called_on_instance")
	shown_level = GameState.level_for_xp(xp0)
	_set_xp_display(float(xp0))

	var t := create_tween()
	t.tween_property(card, "modulate:a", 1.0, 0.35).set_delay(0.65)
	var dur : float = clampf(float(xp1 - xp0) * 0.004, 0.7, 1.8)
	t.tween_method(_set_xp_display, float(xp0), float(xp1), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _set_xp_display(v: float) -> void:
	var xp  := int(v)
	@warning_ignore("static_called_on_instance")
	var lvl := GameState.level_for_xp(xp)
	if lvl != shown_level:
		shown_level = lvl
		Sfx.play_best()
		xp_level_label.scale = Vector2(1.35, 1.35)
		var pt := create_tween()
		pt.tween_property(xp_level_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if lvl >= GameState.MAX_LEVEL:
		xp_level_label.text = "LEVEL " + str(lvl) + " (MAX)"
		xp_fill.size.x = XP_BAR_W
		xp_gloss.size.x = maxf(XP_BAR_W - 6.0, 0.0)
		xp_count_label.text = "MAX LEVEL"
		return
	xp_level_label.text = "LEVEL " + str(lvl)
	@warning_ignore("static_called_on_instance")
	var prog : Array = GameState.progress_for_xp(xp)
	xp_fill.size.x = XP_BAR_W * clampf(float(prog[0]) / float(maxi(prog[1], 1)), 0.0, 1.0)
	xp_gloss.size.x = maxf(xp_fill.size.x - 6.0, 0.0)
	xp_count_label.text = str(prog[0]) + " / " + str(prog[1]) + " XP"

func _show_achievement_toast(id: String, delay: float) -> void:
	var a : Dictionary = GameState.ach_info(id)
	if a.is_empty():
		return
	var is_skin : bool = a.get("skin", false)
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
	t.tween_interval(delay)
	t.tween_callback(Sfx.play_best)
	t.tween_property(panel, "position:y", 20.0, 0.40).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(2.2)
	t.tween_property(panel, "position:y", -110.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(panel.queue_free)

func _count_tick(v: float) -> void:
	var s := str(int(v))
	score_label.text = s
	var fs := 110
	if   s.length() >= 7: fs = 66
	elif s.length() == 6: fs = 80
	elif s.length() == 5: fs = 96
	score_label.add_theme_font_size_override("font_size", fs)
	score_label.scale = Vector2.ONE * (1.0 + fmod(v, 7.0) * 0.004)

func _start_best_shimmer() -> void:
	best_label.pivot_offset = best_label.size * 0.5
	var t := create_tween().set_loops()
	t.tween_property(best_label, "modulate", Color(1.0, 1.0, 0.7, 1.0), 0.45).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(best_label, "scale", Vector2(1.10, 1.10), 0.45).set_trans(Tween.TRANS_SINE)
	t.tween_property(best_label, "modulate", Color(1, 1, 1, 1), 0.45).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(best_label, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_SINE)

func _style_buttons() -> void:
	_chunky(ad_button,    Color(0.20, 0.85, 0.45))
	_chunky(retry_button, Color(0.20, 0.75, 0.95))
	_chunky(menu_button,  Color(0.55, 0.45, 0.75))
	for b in [ad_button, retry_button, menu_button]:
		b.modulate.a = 0.0
	var t := create_tween()
	t.tween_interval(0.8)
	t.tween_property(ad_button,    "modulate:a", 1.0, 0.3)
	t.tween_property(retry_button, "modulate:a", 1.0, 0.25)
	t.tween_property(menu_button,  "modulate:a", 1.0, 0.25)

func _chunky(b: Button, fill: Color) -> void:
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
	var fc := Color(0.08, 0.06, 0.12)
	b.add_theme_color_override("font_color", fc)
	b.add_theme_color_override("font_hover_color", fc)
	b.add_theme_color_override("font_pressed_color", fc)
	_add_press_effect(b)

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

func _process(delta: float) -> void:
	for orb in orbs:
		orb["pos"] += orb["vel"] * delta
		if orb["pos"].x < -140.0 or orb["pos"].x > 554.0: orb["vel"].x = -orb["vel"].x
		if orb["pos"].y < -140.0 or orb["pos"].y > 1036.0: orb["vel"].y = -orb["vel"].y
	for i in fallers.size():
		var f : Dictionary = fallers[i]
		f["pos"].y += f["spd"] * delta
		f["rot"]   += f["rspd"] * delta
		if f["pos"].y > 950.0:
			f["pos"]  = Vector2(randf() * 414.0, -50.0)
	queue_redraw()
	faller_layer.queue_redraw()

func _draw() -> void:
	var skin := GameState.effective_skin(GameState.theme_idx)
	var bg : Color = GameState.THEMES[skin % GameState.THEMES.size()]["bg"]
	draw_rect(Rect2(Vector2.ZERO, Vector2(414, 896)), bg.darkened(0.35), true)
	for orb in orbs:
		draw_circle(orb["pos"], orb["radius"], orb["color"])

func _draw_fallers() -> void:
	var style := GameState.effective_skin(GameState.theme_idx)
	for f in fallers:
		faller_layer.draw_set_transform(f["pos"], f["rot"])
		var cs : float = f["cs"]
		for cell in f["shape"]:
			BlockSkins.paint(faller_layer, style,
				Rect2(cell[0] * cs, cell[1] * cs, cs - 1.0, cs - 1.0),
				f["color"], f["seed"] + cell[0] * 7 + cell[1] * 13)
	faller_layer.draw_set_transform(Vector2.ZERO)

func _build_leaderboard() -> void:
	var scores := GameState.scores
	if scores.is_empty():
		return

	var header := Label.new()
	header.text = "— TOP SCORES —"
	header.add_theme_font_size_override("font_size", 13)
	header.add_theme_color_override("font_color", Color(1, 1, 1, 0.30))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.size = Vector2(300, 22)
	header.position = Vector2(57, 490)
	ui.add_child(header)

	var top_n : int = min(scores.size(), 3)
	for i in top_n:
		var lbl := Label.new()
		var is_current : bool = (scores[i] == GameState.last_score and i == 0)
		lbl.text = "#%d    %d" % [i + 1, scores[i]]
		lbl.add_theme_font_size_override("font_size", 20)
		var col : Color
		if i == 0:
			col = Color(0.95, 0.85, 0.15, 0.95)
		elif is_current:
			col = Color(0.20, 0.85, 0.45, 0.9)
		else:
			col = Color(1, 1, 1, 0.45 - i * 0.06)
		lbl.add_theme_color_override("font_color", col)
		lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.09, 0.8))
		lbl.add_theme_constant_override("outline_size", 4)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.size = Vector2(300, 28)
		lbl.position = Vector2(57 - 340, 514.0 + i * 30.0)
		ui.add_child(lbl)
		# Slide rows in from the left, staggered
		var t := create_tween()
		t.tween_interval(0.5 + float(i) * 0.08)
		t.tween_property(lbl, "position:x", 57.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_watch_ad_pressed() -> void:
	Sfx.play_click()
	ad_button.disabled = true
	if ad_mode == "double_xp":
		Ads.show_rewarded(func(earned: bool):
			if earned:
				_grant_double_xp()
			else:
				# Closed early or no fill — no bonus
				ad_button.disabled = false
				ad_button.text = "AD NOT FINISHED — TRY AGAIN")
		return
	# Revive
	Ads.show_rewarded(func(earned: bool):
		if earned:
			GameState.continue_mode = "ad"
			get_tree().change_scene_to_file("res://scenes/Game.tscn")
		else:
			# Closed early or no fill — no revive
			ad_button.disabled = false
			ad_button.text = "AD NOT FINISHED — TRY AGAIN")

func _grant_double_xp() -> void:
	if _dx_claimed:
		return
	_dx_claimed = true
	var before : int = GameState.player_xp
	GameState.grant_double_xp()
	# Re-animate the XP bar from its current fill up to the doubled total
	xp_gain_label.text = "+" + str(GameState.last_xp_gain) + " XP"
	xp_gain_label.pivot_offset = xp_gain_label.size * 0.5
	var pop := create_tween()
	pop.tween_property(xp_gain_label, "scale", Vector2(1.3, 1.3), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(xp_gain_label, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK)
	var t := create_tween()
	t.tween_method(_set_xp_display, float(before), float(GameState.player_xp), 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	Sfx.play_best()
	# Retire the ad button so it can't be tapped again
	ad_button.disabled = true
	ad_button.text = "XP DOUBLED!"
	var ft := create_tween()
	ft.tween_interval(0.7)
	ft.tween_property(ad_button, "modulate:a", 0.0, 0.3)
	ft.tween_callback(func(): ad_button.visible = false)

func _on_retry_pressed() -> void:
	Sfx.play_click()
	GameState.has_save = false
	get_tree().change_scene_to_file("res://scenes/Game.tscn")

func _on_menu_pressed() -> void:
	Sfx.play_click()
	GameState.has_save = false
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
