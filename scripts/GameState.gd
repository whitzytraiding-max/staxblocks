extends Node

var last_score : int   = 0
var best_score : int   = 0
var scores     : Array = []   # top MAX_SCORES, sorted descending

# Settings
var sound_on   : bool = true
var music_on   : bool = true
var haptics_on : bool = true

# One ad-revive per run
var revive_used : bool = false

# First-run tutorial: tutorial_active (runtime) launches Game straight into the
# coached tutorial; tutorial_done (persisted) stops it ever replaying.
var tutorial_active : bool = false
var tutorial_done   : bool = false

# In-app review prompt: 0 = not asked, 1 = snoozed ("maybe later"), 2 = done /
# rated / "don't ask again". review_snooze_games stores games_played at snooze
# time so we can re-ask after a few more runs. Both persisted.
var review_state        : int = 0
var review_snooze_games : int = 0

# Player biome (skin) choice from the Biomes gallery (persisted).
#   picked_skin  = the chosen skin index (-1 = none chosen yet)
#   skin_locked  = stay on picked_skin (no rotation). When false, AUTO still
#                  cycles through the unlocked set as rows clear.
var picked_skin : int  = -1
var skin_locked : bool = false

# AUTO-mode skin cycling uses a shuffle bag: every unlocked skin appears once
# before any repeats. Persisted so the cycle carries across runs.
var theme_bag : Array = []

# ── Secret cat skin (easter egg: tap S-T-A-X on the title in order) ───────────
# CAT is the last THEMES entry; the random theme rotation only uses 0..CAT_SKIN-1
# so it never appears by chance. cat_mode forces it on everywhere, and persists.
const CAT_SKIN := 30
var cat_mode : bool = false

# Effective skin index, honoured by Game/MainMenu/GameOver
func active_skin(theme_i: int) -> int:
	return effective_skin(theme_i)

# Single source of truth for "which skin to show" given the rotation index.
# Priority: cat easter egg > player lock > AUTO rotation.
func effective_skin(rot: int) -> int:
	if cat_mode:
		return CAT_SKIN
	if skin_locked and picked_skin >= 0:
		return picked_skin
	return rot % THEMES.size()

# Player taps an unlocked biome in the gallery. Switches to it now; when not
# locked, AUTO rotation simply carries on from here through the unlocked set.
func select_skin(idx: int) -> void:
	if not is_skin_unlocked(idx):
		return
	picked_skin       = idx
	theme_idx         = idx
	theme_bag         = []     # reshuffle so the pick doesn't instantly repeat
	_save()

func set_skin_locked(on: bool) -> void:
	skin_locked = on
	# Locking with nothing chosen yet pins the current biome
	if on and (picked_skin < 0 or not is_skin_unlocked(picked_skin)):
		picked_skin = theme_idx % THEMES.size()
	_save()

# Human-readable unlock requirement for a locked biome ("" = starter / unlocked)
func skin_unlock_hint(idx: int) -> String:
	var rule : String = SKIN_UNLOCK.get(idx, "start")
	if rule == "start":
		return ""
	if rule.begins_with("L"):
		return "Reach level " + rule.substr(1)
	var g := ach_group(rule)
	if g.is_empty():
		return ""
	return "Complete " + str(g["name"])

func set_cat_mode(on: bool) -> void:
	cat_mode = on
	_save()

# ── Skin unlocks (4 tiers: Starter / T1 / T2 / T3) ────────────────────────────
# Rule per skin: "start" (have from the off), "L<n>" (reach level n), or
# "<ach_group>" (complete that achievement's LAST/hardest tier). Index = skin idx.
# Difficulty climbs Starter -> T1 -> T2 -> T3; T3 = top levels + hardest missions.
const SKIN_UNLOCK : Dictionary = {
	# Starter — free from the start
	0:  "start",  1:  "start",  2:  "start",  3:  "start",  4:  "start",
	# Tier 1 — early levels
	5:  "L3",     6:  "L5",     7:  "L7",     8:  "L9",     10: "L12",    13: "L15",    18: "L18",
	# Tier 2 — mid / high levels
	9:  "L22",    12: "L26",    14: "L30",    28: "L34",    22: "L38",    19: "L43",
	27: "L48",    17: "L53",    26: "L58",    29: "L64",
	# Tier 3 — top levels + hardest mission completions
	16: "L70",    20: "L80",    11: "L90",
	25: "score",  24: "marathon", 23: "boards", 21: "multi",  15: "powers",
}

func is_skin_unlocked(idx: int) -> bool:
	if idx >= CAT_SKIN:
		return true
	var rule : String = SKIN_UNLOCK.get(idx, "start")
	if rule == "start":
		return true
	if rule.begins_with("L"):
		return get_level() >= int(rule.substr(1))
	# Achievement skin: requires the FULL quest (its last tier) complete — a real
	# long-term chase rather than an easy first-tier unlock.
	var g := ach_group(rule)
	if g.is_empty():
		return false
	return unlocked.get("%s_%d" % [rule, g["tiers"].size() - 1], false)

func count_unlocked_skins() -> int:
	var n := 0
	for i in CAT_SKIN:
		if is_skin_unlocked(i):
			n += 1
	return n

# Skins newly unlocked since last check — appends "skin_<idx>" toast keys to
# pending_toasts and remembers them so each only announces once.
func check_skin_unlocks() -> Array:
	var fresh : Array = []
	for i in CAT_SKIN:
		if is_skin_unlocked(i) and not skins_seen.has(i):
			skins_seen.append(i)
			fresh.append("skin_%d" % i)
	if not fresh.is_empty():
		_save()
	return fresh

# Skins available for the AUTO rotation = the player's unlocked set
func unlocked_skins() -> Array:
	var pool : Array = []
	for i in CAT_SKIN:   # 0 .. CAT_SKIN-1, never the secret cat
		if is_skin_unlocked(i):
			pool.append(i)
	if pool.is_empty():
		pool.append(0)
	return pool

# Next AUTO skin via a shuffle bag: returns each unlocked skin once before any
# repeat. Refills + reshuffles when empty, avoiding an immediate repeat.
func next_auto_theme(current: int) -> int:
	if theme_bag.is_empty():
		theme_bag = unlocked_skins()
		theme_bag.shuffle()
		if theme_bag.size() > 1 and int(theme_bag[0]) == current:
			theme_bag.push_back(theme_bag.pop_front())
	var nxt : int = int(theme_bag.pop_front())
	_save()
	return nxt

# ── Player profile / XP ───────────────────────────────────────────────────────
# Level curve: cost(level→level+1) = 60 + 0.75·level². Total to hit MAX_LEVEL
# is ~252k XP. Run XP is SKILL-based (score only, no per-move grind): score/400,
# so a strong 15k game pays ~37 and a great 100k run ~250. Hard achievements
# stay the big chunks — levelling is gated by skill, not time spent.
const MAX_LEVEL := 100
# Bump this to force a one-time progress wipe for everyone on the next update:
# on load, a save with an older epoch is reset to a fresh level 1 (settings kept).
const RESET_EPOCH := 2
var save_epoch : int = 0
var player_name  : String = ""
var player_xp    : int = 0
var games_played : int = 0
var unlocked     : Dictionary = {}   # achievement id -> true
var pending_toasts : Array = []      # achievements unlocked at game over (shown on GameOver)
var last_xp_gain   : int = 0
var last_xp_before : int = 0         # XP before the run's payout — drives the bar animation

# Online leaderboard identity (anonymous — no login). player_id is a device UUID;
# friend_code is the short shareable code others enter to add you. Both persisted.
var player_id   : String = ""
var friend_code : String = ""
var my_global_rank : int = 0   # last-known global leaderboard rank (0 = unknown); drives the profile pin
const _CODE_ALPHABET := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"   # no ambiguous 0/O/1/I/L

# Account (Supabase Auth) — present once the player signs in to back up progress.
var auth_refresh_token : String = ""
var auth_provider      : String = ""   # "apple" | "google"

func set_global_rank(r: int) -> void:
	if r > 0 and r != my_global_rank:
		my_global_rank = r
		_save()

func set_auth(refresh_token: String, provider: String) -> void:
	auth_refresh_token = refresh_token
	auth_provider = provider
	_save()

func clear_auth() -> void:
	auth_refresh_token = ""
	auth_provider = ""
	_save()

# Reinstall / new device: adopt the account's durable id so the leaderboard row + friends reattach.
func adopt_account(pid: String, code: String) -> void:
	if pid != "":
		player_id = pid
	if code != "":
		friend_code = code
	_save()

# Snapshot of progress uploaded to the account profile.
func cloud_snapshot() -> Dictionary:
	return {
		"best_score": best_score, "player_xp": player_xp, "games_played": games_played,
		"total_score": total_score, "total_lines": total_lines,
		"stat_blocks": stat_blocks, "stat_best_streak": stat_best_streak,
		"stat_run_lines": stat_run_lines, "stat_board_clears": stat_board_clears,
		"stat_best_multi": stat_best_multi, "stat_revives": stat_revives,
		"stat_powers_used": stat_powers_used,
		"unlocked": unlocked, "skins_seen": skins_seen,
		"tutorial_done": tutorial_done, "player_name": player_name,
		"theme_idx": theme_idx, "picked_skin": picked_skin, "skin_locked": skin_locked,
	}

# Merge a cloud snapshot into local state — field-wise MAX so a high score on any
# device always survives; unlocks/skins union; tutorial flag OR'd. Then persist.
func apply_cloud_profile(d: Dictionary, restoring: bool = false) -> void:
	best_score        = maxi(best_score,        int(d.get("best_score", 0)))
	player_xp         = maxi(player_xp,         int(d.get("player_xp", 0)))
	games_played      = maxi(games_played,      int(d.get("games_played", 0)))
	total_score       = maxi(total_score,       int(d.get("total_score", 0)))
	total_lines       = maxi(total_lines,       int(d.get("total_lines", 0)))
	stat_blocks       = maxi(stat_blocks,       int(d.get("stat_blocks", 0)))
	stat_best_streak  = maxi(stat_best_streak,  int(d.get("stat_best_streak", 0)))
	stat_run_lines    = maxi(stat_run_lines,    int(d.get("stat_run_lines", 0)))
	stat_board_clears = maxi(stat_board_clears, int(d.get("stat_board_clears", 0)))
	stat_best_multi   = maxi(stat_best_multi,   int(d.get("stat_best_multi", 0)))
	stat_revives      = maxi(stat_revives,      int(d.get("stat_revives", 0)))
	stat_powers_used  = maxi(stat_powers_used,  int(d.get("stat_powers_used", 0)))
	tutorial_done     = tutorial_done or bool(d.get("tutorial_done", false))
	var u : Variant = d.get("unlocked", {})
	if u is Dictionary:
		for k in u:
			unlocked[k] = true
	var ss : Variant = d.get("skins_seen", [])
	if ss is Array:
		for v in ss:
			if not skins_seen.has(v):
				skins_seen.append(v)
	# Name: on a RESTORE (existing account) the account's name is the source of
	# truth — bring it back even over a local placeholder like "PLAYER". On a
	# first-time backup (linking a guest) only fill it if we don't have one yet.
	var nm := str(d.get("player_name", ""))
	if nm != "" and (restoring or player_name == "" or player_name == "PLAYER"):
		player_name = nm
	_save()

# Lifetime stats (profile card → stats panel, achievement quest values)
var total_score       : int = 0     # every run's final score summed
var stat_blocks       : int = 0     # total pieces placed
var stat_best_streak  : int = 0     # longest clear streak ever
var stat_run_lines    : int = 0     # most lines cleared in a single run
var stat_board_clears : int = 0     # lifetime full-board clears
var stat_best_multi   : int = 0     # most lines cleared in ONE move
var stat_revives      : int = 0     # lifetime ad-revives used
var stat_powers_used  : int = 0     # lifetime power abilities fired
var skins_seen        : Array = []  # skin indices already announced (for unlock toasts)

func add_revive() -> void:
	stat_revives += 1
	_save()

func add_power_used() -> void:
	stat_powers_used += 1
	_save()

# ── Achievements (tiered, Clash-style) ────────────────────────────────────────
# Each group is ONE quest with escalating tiers [target, xp]. The menu shows
# only the current tier; tapping a card expands the full ladder. Unlock keys
# are "<group>_<tier_index>".
const ACH_GROUPS : Array = [
	{"id": "games",  "name": "Dedicated",      "desc": "Play %s games",                  "tiers": [[1, 50], [10, 200], [100, 600]]},
	{"id": "score",  "name": "High Scorer",    "desc": "Score %s in one run",            "tiers": [[10000, 75], [100000, 300], [500000, 900]]},
	{"id": "lines",  "name": "Line Clearer",   "desc": "Clear %s lines in total",        "tiers": [[50, 50], [500, 150], [2500, 350]]},
	{"id": "streak", "name": "On Fire",        "desc": "Reach a streak of %s clears",    "tiers": [[3, 50], [5, 150], [8, 300]]},
	{"id": "multi",  "name": "Combo King",     "desc": "Clear %s lines in one move",     "tiers": [[2, 75], [4, 300], [5, 700]]},
	{"id": "blocks", "name": "Master Builder", "desc": "Place %s blocks in total",       "tiers": [[100, 50], [1000, 150], [10000, 500]]},
	{"id": "boards", "name": "Clean Sweep",    "desc": "Empty the whole board %s times", "tiers": [[5, 100], [25, 300], [50, 800]]},
	# Climber + Collector are PROGRESSION milestones (level / skins are downstream
	# of XP) — they grant 0 XP so completing them can't feed back into more levels.
	{"id": "level",  "name": "Climber",        "desc": "Reach level %s",                 "tiers": [[25, 0], [50, 0], [75, 0]]},
	{"id": "powers", "name": "Powerhouse",     "desc": "Use %s abilities",               "tiers": [[25, 100], [100, 350], [250, 800]]},
	{"id": "marathon","name": "Marathon",      "desc": "Clear %s lines in one run",      "tiers": [[30, 100], [75, 300], [150, 600]]},
	{"id": "collector","name": "Collector",    "desc": "Unlock %s skins",                "tiers": [[6, 0], [14, 0], [24, 0]]},
	{"id": "revive", "name": "Second Wind",    "desc": "Continue a run with a revive",   "tiers": [[1, 100]]},
]
const TIER_NUMERALS : Array = ["I", "II", "III"]

static func fmt(n: int) -> String:
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

# Live value backing each quest group
func ach_value(group_id: String) -> int:
	match group_id:
		"games":  return games_played
		"score":  return best_score
		"lines":  return total_lines
		"streak": return stat_best_streak
		"multi":  return stat_best_multi
		"blocks": return stat_blocks
		"boards": return stat_board_clears
		"level":  return get_level()
		"powers": return stat_powers_used
		"marathon": return stat_run_lines
		"collector": return count_unlocked_skins()
		"revive": return stat_revives
	return 0

static func ach_group(group_id: String) -> Dictionary:
	for g in ACH_GROUPS:
		if g["id"] == group_id:
			return g
	return {}

# Display info for an unlock key like "score_1", or a skin unlock "skin_<idx>"
func ach_info(key: String) -> Dictionary:
	if key.begins_with("skin_"):
		var si := int(key.substr(5))
		var nm : String = THEMES[si]["name"] if si < THEMES.size() else "NEW SKIN"
		return {"name": nm, "desc": "New skin unlocked", "xp": 0, "skin": true}
	var sep := key.rfind("_")
	var g := ach_group(key.substr(0, sep))
	if g.is_empty():
		return {}
	var ti := int(key.substr(sep + 1))
	var tier : Array = g["tiers"][ti]
	var nm : String = g["name"]
	if g["tiers"].size() > 1:
		nm += " " + TIER_NUMERALS[ti]
	var d : String = g["desc"]
	if d.contains("%s"):
		d = d % fmt(tier[0])
	return {"name": nm, "desc": d, "xp": tier[1]}

# Walk every tier of every group, unlock anything earned, grant the XP.
# Loops until stable: an XP grant can raise the level (Climber) or unlock a skin
# (Collector), which can unlock more — so one call settles the whole cascade and
# the next call returns nothing. Returns the freshly unlocked keys (for toasts).
func check_unlocks(grant_xp: bool = true) -> Array:
	var all_fresh : Array = []
	while true:
		var fresh : Array = []
		for g in ACH_GROUPS:
			var v := ach_value(g["id"])
			for ti in g["tiers"].size():
				var key := "%s_%d" % [g["id"], ti]
				if unlocked.get(key, false):
					continue
				if v >= g["tiers"][ti][0]:
					unlocked[key] = true
					if grant_xp:
						player_xp += g["tiers"][ti][1]
					fresh.append(key)
		if fresh.is_empty():
			break
		all_fresh.append_array(fresh)
	if not all_fresh.is_empty():
		_save()
	return all_fresh

static func xp_cost(level: int) -> int:
	return 60 + int(0.75 * float(level * level))

static func level_for_xp(xp: int) -> int:
	var lvl := 1
	var rem := xp
	while lvl < MAX_LEVEL and rem >= xp_cost(lvl):
		rem -= xp_cost(lvl)
		lvl += 1
	return lvl

# [xp into current level, xp needed for next level] — [0, 0] at max level
static func progress_for_xp(xp: int) -> Array:
	var lvl := 1
	var rem := xp
	while lvl < MAX_LEVEL and rem >= xp_cost(lvl):
		rem -= xp_cost(lvl)
		lvl += 1
	if lvl >= MAX_LEVEL:
		return [0, 0]
	return [rem, xp_cost(lvl)]

func get_level() -> int:
	return level_for_xp(player_xp)

func xp_progress() -> Array:
	return progress_for_xp(player_xp)

func set_player_name(n: String) -> void:
	player_name = n.strip_edges().substr(0, 12)
	_save()
	_sync_online()   # update our display name on the leaderboard

# Called once per game over: grants run XP, rolls lifetime stats and checks
# games-played milestones
func finish_run(moves: int, final_score: int, run_lines: int = 0,
		run_streak: int = 0, run_boards: int = 0) -> void:
	games_played += 1
	total_score       += final_score
	stat_blocks       += moves
	stat_board_clears += run_boards
	stat_best_streak   = maxi(stat_best_streak, run_streak)
	stat_run_lines     = maxi(stat_run_lines, run_lines)
	last_xp_before = player_xp
	# Skill-based run XP: score only (no per-move grind reward), heavily scaled down.
	last_xp_gain = int(final_score / 400)
	player_xp += last_xp_gain
	pending_toasts = check_unlocks()
	pending_toasts.append_array(check_skin_unlocks())
	_save()

# Watched the "double XP" rewarded ad on a terminal game over (revive already
# spent). Adds the run's XP gain a second time so the payout is 2×. Returns the
# bonus granted. Only meaningful immediately after finish_run, same run.
func grant_double_xp() -> int:
	var bonus := last_xp_gain
	player_xp   += bonus
	last_xp_gain += bonus
	_save()
	return bonus

# ── In-app review prompt gating ──────────────────────────────────────────────
# Ask once after the tutorial's first full run, then re-ask a few runs later if
# they snoozed. Never again once they've rated or chosen "don't ask again".
func should_ask_review() -> bool:
	if not tutorial_done or games_played < 1 or review_state == 2:
		return false
	if review_state == 0:
		return true
	return games_played >= review_snooze_games + 3   # snoozed → re-ask later

func snooze_review() -> void:
	review_state = 1
	review_snooze_games = games_played
	_save()

func finish_review() -> void:   # rated or "don't ask again" → never again
	review_state = 2
	_save()

# Theme progression persists across runs — backgrounds keep rotating
# no matter how short each game is
var theme_idx   : int = 0
var total_lines : int = 0

# In-memory continuation snapshot (ad-continue and run-resume both use it)
# continue_mode: "ad" = gift 2 cleared rows on restore, "resume" = exact restore
var has_save           : bool   = false
var continue_mode      : String = "resume"
var save_cells         : Array  = []
var save_score         : int    = 0
var save_pieces        : Array  = []
var save_placed        : Array  = []
var save_sets_given    : int    = 0
var save_lines_cleared : int    = 0
var save_theme_idx     : int    = 0
var save_combo         : int    = 0
var save_placements    : int    = 0
var save_max_combo     : int    = 0
var save_board_clears  : int    = 0
var save_seeds         : Array  = []   # per-cell skin pattern seeds
var save_meter         : float  = 0.0  # power-meter charge (0..1)

const SAVE_PATH  := "user://stax_save.dat"
const SAVE_TMP   := "user://stax_save.dat.tmp"   # written first, then promoted (atomic-ish)
const SAVE_BAK   := "user://stax_save.dat.bak"   # last known-good, recovered from on corruption
const RUN_PATH   := "user://stax_run.dat"
const MAX_SCORES := 10

# ── Themes ────────────────────────────────────────────────────────────────────
# Lives here (autoload) so Game AND the menus can read it — menu backgrounds
# follow the selected skin. Index = skin index. Brightened across the board;
# only VOLCANO and GALAXY stay dark by design.
# "accent" tints in-game text (clear popups, streak label, theme popup) so
# each theme's typography matches its world
const THEMES: Array = [
	{"bg": Color(0.45, 0.66, 0.86), "orb": Color(1.00, 1.00, 1.00, 0.08), "accent": Color(1.00, 1.00, 1.00), "name": "PASTEL SKY"},
	{"bg": Color(0.12, 0.27, 0.16), "orb": Color(0.20, 1.00, 0.45, 0.08), "accent": Color(0.40, 1.00, 0.60), "name": "NEON JUNGLE"},
	{"bg": Color(0.09, 0.23, 0.20), "orb": Color(0.20, 0.95, 0.65, 0.08), "accent": Color(0.35, 1.00, 0.80), "name": "CIRCUIT CITY"},
	{"bg": Color(0.29, 0.14, 0.11), "orb": Color(0.95, 0.45, 0.25, 0.08), "accent": Color(1.00, 0.65, 0.45), "name": "BRICKYARD"},
	{"bg": Color(0.15, 0.21, 0.37), "orb": Color(0.40, 0.65, 1.00, 0.08), "accent": Color(0.60, 0.80, 1.00), "name": "CRYSTAL CAVE"},
	{"bg": Color(0.37, 0.16, 0.27), "orb": Color(1.00, 0.45, 0.70, 0.08), "accent": Color(1.00, 0.60, 0.82), "name": "CANDY LAND"},
	{"bg": Color(0.15, 0.26, 0.36), "orb": Color(0.80, 0.95, 1.00, 0.08), "accent": Color(0.80, 0.95, 1.00), "name": "FROZEN PEAK"},
	{"bg": Color(0.13, 0.28, 0.15), "orb": Color(0.45, 0.95, 0.35, 0.08), "accent": Color(0.65, 1.00, 0.50), "name": "MEADOW"},
	{"bg": Color(0.10, 0.21, 0.38), "orb": Color(0.25, 0.65, 1.00, 0.08), "accent": Color(0.50, 0.82, 1.00), "name": "OCEAN"},
	{"bg": Color(0.11, 0.03, 0.02), "orb": Color(1.00, 0.35, 0.05, 0.08), "accent": Color(1.00, 0.58, 0.25), "name": "VOLCANO"},
	{"bg": Color(0.27, 0.19, 0.10), "orb": Color(0.85, 0.60, 0.25, 0.07), "accent": Color(0.98, 0.80, 0.50), "name": "TIMBER"},
	{"bg": Color(0.05, 0.02, 0.10), "orb": Color(0.75, 0.35, 1.00, 0.07), "accent": Color(0.85, 0.55, 1.00), "name": "GALAXY"},
	{"bg": Color(0.25, 0.17, 0.05), "orb": Color(1.00, 0.75, 0.20, 0.08), "accent": Color(1.00, 0.82, 0.35), "name": "THE HIVE"},
	{"bg": Color(0.07, 0.06, 0.13), "orb": Color(0.40, 1.00, 0.90, 0.08), "accent": Color(0.45, 1.00, 0.85), "name": "ARCADE"},
	{"bg": Color(0.20, 0.30, 0.42), "orb": Color(1.00, 1.00, 1.00, 0.09), "accent": Color(0.85, 0.95, 1.00), "name": "BUBBLE BATH"},
	{"bg": Color(0.13, 0.15, 0.23), "orb": Color(0.60, 0.70, 0.90, 0.08), "accent": Color(0.75, 0.85, 1.00), "name": "THUNDERSTORM"},
	{"bg": Color(0.33, 0.18, 0.24), "orb": Color(1.00, 0.70, 0.80, 0.08), "accent": Color(1.00, 0.75, 0.85), "name": "BLOSSOM"},
	{"bg": Color(0.19, 0.14, 0.06), "orb": Color(1.00, 0.85, 0.40, 0.07), "accent": Color(1.00, 0.85, 0.45), "name": "THE VAULT"},
	{"bg": Color(0.10, 0.18, 0.08), "orb": Color(0.50, 0.90, 0.30, 0.08), "accent": Color(0.62, 1.00, 0.42), "name": "SWAMP"},
	{"bg": Color(0.11, 0.05, 0.15), "orb": Color(0.90, 0.40, 1.00, 0.08), "accent": Color(1.00, 0.50, 0.90), "name": "DANCE FLOOR"},
	{"bg": Color(0.04, 0.07, 0.16), "orb": Color(0.30, 1.00, 0.70, 0.07), "accent": Color(0.50, 1.00, 0.85), "name": "AURORA SKY"},
	{"bg": Color(0.08, 0.04, 0.16), "orb": Color(0.70, 0.40, 1.00, 0.08), "accent": Color(0.85, 0.60, 1.00), "name": "PLASMA FIELD"},
	{"bg": Color(0.26, 0.24, 0.30), "orb": Color(1.00, 1.00, 1.00, 0.06), "accent": Color(0.92, 0.90, 0.96), "name": "MARBLE HALL"},
	{"bg": Color(0.02, 0.08, 0.04), "orb": Color(0.20, 1.00, 0.40, 0.07), "accent": Color(0.40, 1.00, 0.50), "name": "DATA STREAM"},
	{"bg": Color(0.06, 0.07, 0.14), "orb": Color(0.40, 0.90, 1.00, 0.08), "accent": Color(0.60, 0.90, 1.00), "name": "HOLO DECK"},
	{"bg": Color(0.10, 0.10, 0.16), "orb": Color(1.00, 1.00, 1.00, 0.07), "accent": Color(0.80, 0.95, 1.00), "name": "PRISM"},
	{"bg": Color(0.07, 0.06, 0.11), "orb": Color(0.80, 0.45, 1.00, 0.08), "accent": Color(0.95, 0.70, 1.00), "name": "CATHEDRAL"},
	{"bg": Color(0.10, 0.04, 0.16), "orb": Color(1.00, 0.30, 0.80, 0.08), "accent": Color(1.00, 0.45, 0.85), "name": "OUTRUN"},
	{"bg": Color(0.16, 0.09, 0.04), "orb": Color(1.00, 0.55, 0.15, 0.08), "accent": Color(1.00, 0.65, 0.25), "name": "HARVEST"},
	{"bg": Color(0.02, 0.03, 0.09), "orb": Color(0.55, 0.70, 1.00, 0.08), "accent": Color(0.70, 0.85, 1.00), "name": "HYPERSPACE"},
	# index 30 = secret CAT skin (never in random rotation; easter-egg only)
	{"bg": Color(0.20, 0.14, 0.24), "orb": Color(1.00, 0.80, 0.90, 0.09), "accent": Color(1.00, 0.78, 0.88), "name": "MEOW TOWN"},
]

func _ready() -> void:
	# Cap to 60 FPS. Without this, on a 120 Hz ProMotion device (iPhone 16 Pro etc.)
	# the whole game renders at 120 — roughly double the GPU/CPU work, which ran the
	# phone hot and drained the battery. 60 is plenty smooth for a block puzzle, so
	# this is a big power saving with no perceptible quality loss. (Also set in
	# project.godot; this guarantees it regardless of the project-setting key.)
	Engine.max_fps = 60
	_load()
	check_unlocks(false)   # mark already-earned achievements done WITHOUT granting
						   # XP — you only gain levels by playing, not by launching
	check_skin_unlocks()   # mark already-earned skins as seen (no toast flood)
	_ensure_identity()     # device id + friend code for the online leaderboard
	_sync_online()         # push our row up (creates it so friends can add us)

# ── Online identity / leaderboard sync ────────────────────────────────────────
func _ensure_identity() -> void:
	var changed := false
	if player_id == "":
		player_id = _gen_uuid()
		changed = true
	if friend_code == "":
		friend_code = _gen_friend_code()
		changed = true
	if changed:
		_save()

func _gen_uuid() -> String:
	var b := PackedByteArray()
	b.resize(16)
	for i in 16:
		b[i] = randi() & 0xff
	b[6] = (b[6] & 0x0f) | 0x40   # version 4
	b[8] = (b[8] & 0x3f) | 0x80   # variant
	var h := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4),
		h.substr(16, 4), h.substr(20, 12)]

func _gen_friend_code() -> String:
	var s := ""
	for i in 7:
		s += _CODE_ALPHABET[randi() % _CODE_ALPHABET.length()]
	return s

# Push our row to Supabase (no-op until Net is configured). submit_score upserts,
# keeping the server-side max, so re-syncing a lower local best is harmless.
func _sync_online() -> void:
	if player_id == "":
		return
	var nm := player_name if player_name != "" else "PLAYER"
	Net.submit_score(player_id, friend_code, nm, best_score, get_level())

func submit_score(s: int) -> void:
	last_score = s
	if s > best_score:
		best_score = s

func record_final_score(s: int) -> void:
	submit_score(s)
	if s > 0:
		scores.append(s)
		scores.sort()
		scores.reverse()
		if scores.size() > MAX_SCORES:
			scores.resize(MAX_SCORES)
	_save()
	_sync_online()   # push the new best to the online leaderboard

func set_sound(on: bool) -> void:
	sound_on = on
	_save()

func set_music(on: bool) -> void:
	music_on = on
	_save()

func set_haptics(on: bool) -> void:
	haptics_on = on
	_save()

func add_lines(n: int) -> void:
	total_lines += n
	_save()

func set_theme(i: int) -> void:
	theme_idx = i
	_save()

func snapshot(cells: Array, sc: int, pcs: Array, pl: Array,
			  sg: int, lc: int, ti: int, cb: int, pm: int = 0,
			  mc: int = 0, bc: int = 0, sd: Array = [], mt: float = 0.0) -> void:
	has_save           = true
	save_cells         = cells.duplicate(true)
	save_score         = sc
	save_pieces        = pcs.duplicate(true)
	save_placed        = pl.duplicate()
	save_sets_given    = sg
	save_lines_cleared = lc
	save_theme_idx     = ti
	save_combo         = cb
	save_placements    = pm
	save_max_combo     = mc
	save_board_clears  = bc
	save_seeds         = sd.duplicate(true)
	save_meter         = mt

# ── Run persistence (auto-save until the player loses) ───────────────────────
func save_run_to_disk() -> void:
	var f := FileAccess.open(RUN_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_var(save_cells)
	f.store_var(save_score)
	f.store_var(save_pieces)
	f.store_var(save_placed)
	f.store_var(save_sets_given)
	f.store_var(save_lines_cleared)
	f.store_var(save_combo)
	f.store_var(save_placements)
	f.store_var(save_max_combo)
	f.store_var(save_board_clears)
	f.store_var(revive_used)
	f.store_var(save_seeds)
	f.store_var(save_meter)
	f.close()

func has_run_save() -> bool:
	return FileAccess.file_exists(RUN_PATH)

func load_run_from_disk() -> bool:
	if not FileAccess.file_exists(RUN_PATH):
		return false
	var f := FileAccess.open(RUN_PATH, FileAccess.READ)
	if f == null:
		return false
	save_cells         = f.get_var()
	save_score         = f.get_var()
	save_pieces        = f.get_var()
	save_placed        = f.get_var()
	save_sets_given    = f.get_var()
	save_lines_cleared = f.get_var()
	save_combo         = f.get_var()
	save_placements    = f.get_var()
	# Stats + revive flag + seeds added later — older run files end early
	save_max_combo    = f.get_var() if f.get_position() < f.get_length() else 0
	save_board_clears = f.get_var() if f.get_position() < f.get_length() else 0
	revive_used       = f.get_var() if f.get_position() < f.get_length() else false
	save_seeds        = f.get_var() if f.get_position() < f.get_length() else []
	save_meter        = f.get_var() if f.get_position() < f.get_length() else 0.0
	f.close()
	save_theme_idx = theme_idx
	has_save       = true
	continue_mode  = "resume"
	return true

func clear_run() -> void:
	if FileAccess.file_exists(RUN_PATH):
		var d := DirAccess.open("user://")
		if d != null:
			d.remove("stax_run.dat")

# Wipe progression to a fresh level 1 and re-prompt for name. Keeps only settings.
func _reset_progress() -> void:
	player_name = ""
	best_score = 0
	scores = []
	theme_idx = 0
	total_lines = 0
	player_xp = 0
	games_played = 0
	unlocked = {}
	total_score = 0
	stat_blocks = 0
	stat_best_streak = 0
	stat_run_lines = 0
	stat_board_clears = 0
	stat_best_multi = 0
	stat_revives = 0
	stat_powers_used = 0
	cat_mode = false
	theme_bag = []
	skins_seen = []
	picked_skin = -1
	skin_locked = false
	tutorial_done = false
	review_state = 0
	review_snooze_games = 0
	my_global_rank = 0

# ── Settings / meta persistence ───────────────────────────────────────────────
# Crash-safe save: write the whole thing to a temp file, then promote it over the
# live file, keeping the previous good copy as .bak. Because the live file is only
# ever replaced by a fully-written temp, a crash mid-write can never leave it
# truncated — which is what used to trip the epoch reset and wipe everyone's data.
func _save() -> void:
	var f := FileAccess.open(SAVE_TMP, FileAccess.WRITE)
	if f == null:
		return
	f.store_var(best_score)
	f.store_var(scores)
	f.store_var(sound_on)
	f.store_var(music_on)
	f.store_var(theme_idx)
	f.store_var(total_lines)
	f.store_var(haptics_on)
	f.store_var(player_name)
	f.store_var(player_xp)
	f.store_var(games_played)
	f.store_var(unlocked)
	f.store_var(total_score)
	f.store_var(stat_blocks)
	f.store_var(stat_best_streak)
	f.store_var(stat_run_lines)
	f.store_var(stat_board_clears)
	f.store_var(stat_best_multi)
	f.store_var(stat_revives)
	f.store_var(cat_mode)
	f.store_var(theme_bag)
	f.store_var(stat_powers_used)
	f.store_var(skins_seen)
	f.store_var(picked_skin)
	f.store_var(skin_locked)
	f.store_var(save_epoch)
	f.store_var(tutorial_done)
	f.store_var(player_id)
	f.store_var(friend_code)
	f.store_var(review_state)
	f.store_var(review_snooze_games)
	f.store_var(my_global_rank)
	f.store_var(auth_refresh_token)
	f.store_var(auth_provider)
	var write_ok := f.get_error() == OK
	f.close()
	if not write_ok:   # write failed partway (disk full etc) — leave the live file untouched
		return

	var d := DirAccess.open("user://")
	if d == null:
		return
	# Refresh the backup from the current good save before we replace it.
	if d.file_exists(SAVE_PATH):
		if d.file_exists(SAVE_BAK):
			d.remove(SAVE_BAK)
		d.copy(SAVE_PATH, SAVE_BAK)
		d.remove(SAVE_PATH)
	d.rename(SAVE_TMP, SAVE_PATH)

# Index of save_epoch within the optional-tail value list (the two mandatory
# header fields best_score/scores are read separately first).
const _EPOCH_VAL_IDX := 22

func _load() -> void:
	# Prefer the live save; if it's missing or corrupt (e.g. a crash mid-promote),
	# recover from the freshly-written temp or the last-good backup. A COMPLETE read
	# (one that reached the epoch field) always wins over a partial one.
	var best_code := -1
	for path : String in [SAVE_PATH, SAVE_TMP, SAVE_BAK]:
		if not FileAccess.file_exists(path):
			continue
		var c := _read_save_fields(path)
		if c > best_code:
			best_code = c
		if c == 1:
			break   # complete read — good enough, stop looking
	if best_code < 0:
		return   # nothing usable anywhere → genuine fresh install
	# Epoch reset is the one-time pre-rework wipe. ONLY honour it on a COMPLETE read
	# (we reached the epoch field). A short/partial read must NEVER wipe real data —
	# that silent path is what nuked the 300k save.
	if best_code == 1 and save_epoch < RESET_EPOCH:
		_reset_progress()
		save_epoch = RESET_EPOCH
		_save()

# Reads a save file into the live state. Returns -1 if it can't even read the two
# mandatory fields (treat as invalid — caller tries a fallback), 0 if it read a
# valid-but-short save (epoch field not reached), 1 if it reached the epoch field.
# Reads the optional tail generically and stops at the first missing/partial value,
# so a half-written var can never throw or get assigned as null.
func _read_save_fields(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 1:
		if f != null:
			f.close()
		return -1
	var bs : Variant = f.get_var()
	var sc : Variant = f.get_var()
	if not (bs is int or bs is float) or not (sc is Array):
		f.close()
		return -1   # corrupt header — don't touch live state, let caller try a fallback
	best_score = int(bs)
	scores     = sc
	# Read the remaining (optional) fields in order; bail on the first value that's
	# absent or only partially written (get_var → null), since everything after it
	# is gone too. This is the truncation-safe path.
	var vals : Array = []
	while f.get_position() < f.get_length():
		var v : Variant = f.get_var()
		if v == null:
			break
		vals.append(v)
	f.close()

	var n := vals.size()
	if n > 0:  sound_on            = vals[0]
	if n > 1:  music_on            = vals[1]
	if n > 2:  theme_idx           = vals[2]
	if n > 3:  total_lines         = vals[3]
	if n > 4:  haptics_on          = vals[4]
	if n > 5:  player_name         = vals[5]
	if n > 6:  player_xp           = vals[6]
	if n > 7:  games_played        = vals[7]
	if n > 8:  unlocked            = vals[8]
	if n > 9:  total_score         = vals[9]
	if n > 10: stat_blocks         = vals[10]
	if n > 11: stat_best_streak    = vals[11]
	if n > 12: stat_run_lines      = vals[12]
	if n > 13: stat_board_clears   = vals[13]
	if n > 14: stat_best_multi     = vals[14]
	if n > 15: stat_revives        = vals[15]
	if n > 16: cat_mode            = vals[16]
	if n > 17: theme_bag           = vals[17]
	if n > 18: stat_powers_used    = vals[18]
	if n > 19: skins_seen          = vals[19]
	if n > 20: picked_skin         = vals[20]
	if n > 21: skin_locked         = vals[21]
	if n > _EPOCH_VAL_IDX: save_epoch = vals[_EPOCH_VAL_IDX]
	if n > 23: tutorial_done       = vals[23]
	if n > 24: player_id           = vals[24]
	if n > 25: friend_code         = vals[25]
	if n > 26: review_state        = vals[26]
	if n > 27: review_snooze_games = vals[27]
	if n > 28: my_global_rank      = vals[28]
	if n > 29: auth_refresh_token  = vals[29]
	if n > 30: auth_provider       = vals[30]
	return 1 if n > _EPOCH_VAL_IDX else 0
