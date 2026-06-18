extends SceneTree

# Headless smoke test for Grid logic — run with:
#   godot --headless --path . -s res://test_smoke.gd

func _initialize() -> void:
	var grid := Grid.new()
	grid._ready()   # script mode: init cells without entering the tree

	var fails := 0

	# Fill row 3 except the last cell
	for c in 7:
		grid.cells[3][c] = Color.RED

	# A single block completing the row should preview all 8 row cells
	var single : Array = [[0, 0]]
	var lines := grid.get_completed_lines(single, 3, 7)
	if lines.size() != 8:
		print("FAIL get_completed_lines row: got ", lines.size()); fails += 1

	# A block placed elsewhere should preview nothing
	lines = grid.get_completed_lines(single, 0, 0)
	if lines.size() != 0:
		print("FAIL get_completed_lines empty: got ", lines.size()); fails += 1

	# Cross check: fill col 5 except row 3, then the corner piece completes both
	for r in 8:
		if r != 3:
			grid.cells[r][5] = Color.BLUE
	grid.cells[3][5] = null
	grid.cells[3][7] = null
	# Now row 3 is missing cols 5 and 7; col 5 missing row 3.
	var l_shape : Array = [[0, 0]]
	lines = grid.get_completed_lines(l_shape, 3, 5)
	# Placing at (3,5) completes col 5 only (row 3 still missing col 7) -> 8 cells
	if lines.size() != 8:
		print("FAIL get_completed_lines col: got ", lines.size()); fails += 1

	# set_ghost populates preview, clear_ghost wipes it
	grid.set_ghost(single, 3, 5, Color.GREEN)
	if grid.preview_cells.size() != 8:
		print("FAIL set_ghost preview: got ", grid.preview_cells.size()); fails += 1
	grid.clear_ghost()
	if grid.preview_cells.size() != 0 or grid.ghost_cells.size() != 0:
		print("FAIL clear_ghost"); fails += 1

	# place + check_and_clear: complete col 5, expect clear_anim and nulled col.
	# check_and_clear returns CELLS cleared (Game.gd owns point math)
	grid.place(single, 3, 5, Color.GREEN)
	var cleared := grid.check_and_clear()
	if grid.last_lines_cleared != 1:
		print("FAIL lines cleared: ", grid.last_lines_cleared); fails += 1
	if cleared != 8:
		print("FAIL cells cleared: ", cleared); fails += 1
	if grid.clear_anim.size() != 8 or not grid.clearing:
		print("FAIL clear_anim: ", grid.clear_anim.size()); fails += 1
	for r in 8:
		if grid.cells[r][5] != null:
			print("FAIL col not nulled at row ", r); fails += 1

	# Crossing clear: row + col share one cell — must count 15 cells, 2 lines
	var gx := Grid.new()
	gx._ready()
	for c in 8:
		if c != 4: gx.cells[2][c] = Color.RED
	for r in 8:
		if r != 2: gx.cells[r][4] = Color.BLUE
	gx.place(single, 2, 4, Color.GREEN)
	var crossed := gx.check_and_clear()
	if gx.last_lines_cleared != 2:
		print("FAIL cross lines: ", gx.last_lines_cleared); fails += 1
	if crossed != 15:
		print("FAIL cross cells: ", crossed); fails += 1
	gx.free()

	# Squash curve endpoints sane
	var s0 : Vector2 = grid._squash_scale(0.0)
	var s1 : Vector2 = grid._squash_scale(1.0)
	if absf(s1.x - 1.0) > 0.01 or absf(s1.y - 1.0) > 0.01:
		print("FAIL squash settle: ", s1); fails += 1
	if s0.x < 1.2 or s0.y > 0.8:
		print("FAIL squash start: ", s0); fails += 1

	# count_completed_lines: fresh grid, row 0 missing 2 cells, col 0 missing same corner
	var g2 := Grid.new()
	g2._ready()
	for c in range(2, 8):
		g2.cells[0][c] = Color.RED
	for r in range(1, 8):
		g2.cells[r][0] = Color.BLUE
	for r in range(1, 8):
		g2.cells[r][1] = Color.BLUE
	# Placing a 2x1 domino at (0,0)-(0,1) completes row 0 + col 0 + col 1 = 3 lines
	var domino : Array = [[0, 0], [1, 0]]
	var n := g2.count_completed_lines(domino, 0, 0)
	if n != 3:
		print("FAIL count_completed_lines: got ", n); fails += 1
	if g2.count_completed_lines(domino, 4, 4) != 0:
		print("FAIL count_completed_lines empty spot"); fails += 1

	# Fill-count combo math (Game.gd's fast path) must agree with
	# count_completed_lines on randomized boards
	seed(1234)
	var domino2 : Array = [[0, 0], [1, 0], [0, 1]]
	for trial in 30:
		var g3 := Grid.new()
		g3._ready()
		for r in 8:
			for c in 8:
				if randf() < 0.45:
					g3.cells[r][c] = Color.RED
		var row_fill : Array = []
		var col_fill : Array = []
		for r in 8:
			var cnt := 0
			for c in 8:
				if g3.cells[r][c] != null: cnt += 1
			row_fill.append(cnt)
		for c in 8:
			var cnt := 0
			for r in 8:
				if g3.cells[r][c] != null: cnt += 1
			col_fill.append(cnt)
		for r in 8:
			for c in 8:
				if not g3.can_place(domino2, r, c):
					continue
				var rows_touched := {}
				var cols_touched := {}
				for cell in domino2:
					var rr : int = r + cell[1]
					var cc : int = c + cell[0]
					rows_touched[rr] = rows_touched.get(rr, 0) + 1
					cols_touched[cc] = cols_touched.get(cc, 0) + 1
				var fast := 0
				for rr in rows_touched:
					if row_fill[rr] + rows_touched[rr] == 8: fast += 1
				for cc in cols_touched:
					if col_fill[cc] + cols_touched[cc] == 8: fast += 1
				var ref : int = g3.count_completed_lines(domino2, r, c)
				if fast != ref:
					print("FAIL combo math mismatch at trial ", trial, " (", r, ",", c, "): fast=", fast, " ref=", ref)
					fails += 1
		g3.free()

	# GameState run save/load roundtrip (run file only — never touches stax_save.dat)
	var gs = load("res://scripts/GameState.gd").new()
	gs.save_cells = [[Color.RED, null], [null, Color.BLUE]]
	gs.save_score = 1234
	gs.save_pieces = [{"shape": [[0, 0]], "color": Color.GREEN}]
	gs.save_placed = [false, true, false]
	gs.save_sets_given = 4
	gs.save_lines_cleared = 9
	gs.save_combo = 2
	gs.save_placements = 11
	gs.save_run_to_disk()
	if not gs.has_run_save():
		print("FAIL run file not written"); fails += 1
	var gs2 = load("res://scripts/GameState.gd").new()
	gs2.theme_idx = 3
	if not gs2.load_run_from_disk():
		print("FAIL run load"); fails += 1
	if gs2.save_score != 1234 or gs2.save_placements != 11 or gs2.save_combo != 2:
		print("FAIL run roundtrip values"); fails += 1
	if gs2.save_cells[0][0] != Color.RED or gs2.save_cells[1][0] != null:
		print("FAIL run roundtrip cells"); fails += 1
	if not gs2.has_save or gs2.continue_mode != "resume" or gs2.save_theme_idx != 3:
		print("FAIL run load flags"); fails += 1
	gs.clear_run()
	if gs.has_run_save():
		print("FAIL clear_run"); fails += 1

	# XP curve total to level 100 (skill-based income + steeper curve ~168k)
	var total_xp := 0
	for lvl in range(1, 100):
		total_xp += gs.xp_cost(lvl)
	if total_xp < 230000 or total_xp > 285000:
		print("FAIL xp curve total: ", total_xp); fails += 1
	gs.player_xp = 0
	if gs.get_level() != 1:
		print("FAIL level at 0 xp: ", gs.get_level()); fails += 1
	gs.player_xp = total_xp + 5000
	if gs.get_level() != 100:
		print("FAIL max level: ", gs.get_level()); fails += 1
	if gs.xp_progress() != [0, 0]:
		print("FAIL max level progress"); fails += 1
	gs.player_xp = 70   # past level 1 cost (60), 10 into level 2
	if gs.get_level() != 2 or gs.xp_progress()[0] != 10:
		print("FAIL level walk: ", gs.get_level(), " ", gs.xp_progress()); fails += 1

	# Tiered achievements: unlock grants XP exactly once, info formats right.
	# check_unlocks() writes the save file — back up the real one first.
	var had_save := FileAccess.file_exists("user://stax_save.dat")
	var backup : PackedByteArray = PackedByteArray()
	if had_save:
		backup = FileAccess.get_file_as_bytes("user://stax_save.dat")
	gs.player_xp = 0
	gs.unlocked = {}
	gs.best_score = 15000   # past score tier I (10000), short of tier II (100000)
	var fresh : Array = gs.check_unlocks()
	if not fresh.has("score_0") or fresh.has("score_1"):
		print("FAIL tiered unlock: ", fresh); fails += 1
	if gs.player_xp < 75:
		print("FAIL tier xp: ", gs.player_xp); fails += 1
	if not gs.check_unlocks().is_empty():
		print("FAIL double unlock"); fails += 1
	var info : Dictionary = gs.ach_info("score_0")
	if info.get("name", "") != "High Scorer I" or info.get("xp", 0) != 75:
		print("FAIL ach_info: ", info); fails += 1
	gs.best_score = 120000
	if not gs.check_unlocks().has("score_1"):
		print("FAIL next tier unlock"); fails += 1
	if had_save:
		var bf := FileAccess.open("user://stax_save.dat", FileAccess.WRITE)
		bf.store_buffer(backup)
		bf.close()
	else:
		var d := DirAccess.open("user://")
		if d != null:
			d.remove("stax_save.dat")

	gs.free()
	gs2.free()
	g2.free()

	if fails == 0:
		print("SMOKE OK — all Grid checks passed")
	else:
		print("SMOKE FAILED — ", fails, " check(s)")
	quit(0 if fails == 0 else 1)
