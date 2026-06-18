extends Node
## Supabase REST client for the online leaderboard + friends. Pure HTTPS (Godot
## HTTPRequest) so it works identically on iOS and Android with no native plugin.
##
## All DB access goes through SECURITY DEFINER Postgres functions (RPC) — the app
## only ships the public anon key, and the functions never expose player ids, so a
## client can't grief other players (worst case is inflating your OWN score).
##
## SETUP (Jay): create a Supabase project, run the SQL in SUPABASE_SETUP.md, then
## paste the project URL + anon key below.

const SUPABASE_URL      := "https://dftjbfjgyzpfznsfezpa.supabase.co"
const SUPABASE_ANON_KEY := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRmdGpiZmpneXpwZnpuc2ZlenBhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE3MTY3OTksImV4cCI6MjA5NzI5Mjc5OX0.pTygUmelUo33INiODN5p7k9xTgwoYR9OPVy8pLIW28k"

# Emitted with an Array of {rank, name, best_score, level, (is_me)} rows.
signal global_board(rows: Array)
signal friends_board(rows: Array)
# Emitted with the friend's name on success, or "" if the code was invalid.
signal friend_added(friend_name: String)

func is_configured() -> bool:
	return not SUPABASE_URL.begins_with("https://YOUR_PROJECT") \
		and not SUPABASE_ANON_KEY.begins_with("YOUR_")

func _headers() -> PackedStringArray:
	return PackedStringArray([
		"apikey: " + SUPABASE_ANON_KEY,
		"Authorization: Bearer " + SUPABASE_ANON_KEY,
		"Content-Type: application/json",
	])

# Generic RPC call. `cb` is called as cb(ok: bool, result) — result is the parsed
# JSON (Array / Dictionary / scalar) or null. Fire-and-forget if cb is omitted.
func _rpc(fn: String, body: Dictionary, cb: Callable = Callable()) -> void:
	if not is_configured():
		if cb.is_valid():
			cb.call(false, null)
		return
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 10.0
	http.request_completed.connect(
		func(_result: int, code: int, _h: PackedStringArray, data: PackedByteArray):
			http.queue_free()
			var parsed: Variant = null
			if data.size() > 0:
				parsed = JSON.parse_string(data.get_string_from_utf8())
			if cb.is_valid():
				cb.call(code >= 200 and code < 300, parsed)
	)
	var url := SUPABASE_URL + "/rest/v1/rpc/" + fn
	var err := http.request(url, _headers(), HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		http.queue_free()
		if cb.is_valid():
			cb.call(false, null)

# ── Public API ────────────────────────────────────────────────────────────────

# Upsert this player's row (creates it on first call, then keeps the max score).
func submit_score(pid: String, code: String, pname: String, score: int, level: int) -> void:
	_rpc("submit_score", {
		"p_id": pid, "p_code": code, "p_name": pname,
		"p_score": score, "p_level": level,
	})

func fetch_global(limit: int = 50) -> void:
	_rpc("get_global_board", {"p_limit": limit}, func(ok: bool, res: Variant):
		global_board.emit(res if (ok and res is Array) else [])
	)

func fetch_friends(pid: String) -> void:
	_rpc("get_friends_board", {"p_id": pid}, func(ok: bool, res: Variant):
		friends_board.emit(res if (ok and res is Array) else [])
	)

func add_friend(pid: String, code: String) -> void:
	_rpc("add_friend_by_code", {"p_id": pid, "p_code": code.strip_edges().to_upper()},
		func(ok: bool, res: Variant):
			friend_added.emit(res if (ok and res is String) else "")
	)
