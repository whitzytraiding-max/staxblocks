extends Node
## Account sign-in (Apple / Google via Supabase Auth) so progress survives uninstall.
## OAuth web flow + PKCE — pure HTTPS, no native SDK. Flow:
##   begin_sign_in() opens the browser to Supabase's authorize endpoint →
##   the user signs in → Supabase redirects to AUTH_REDIRECT with ?code=… →
##   we exchange the code (+ PKCE verifier) for a session → link_or_get_profile.
##
## Godot can't natively catch a stax:// redirect without a plugin, so the TEST build
## uses a paste-the-code fallback: set AUTH_REDIRECT to a page that shows the code
## (see SUPABASE_SETUP.md), the player copies it and pastes it into the app. The
## seamless deep-link version calls handle_redirect() from native code later.

signal signed_in(restored: bool)        # restored=true if the account already had a profile
signal sign_in_failed(reason: String)
signal signed_out()

# Where Supabase sends the browser after auth. For the TEST build set this to your
# hosted code page (the HTML in SUPABASE_SETUP.md, dropped on Netlify) so the player
# can copy the code and paste it in. For the seamless deep-link build: "stax://auth".
const AUTH_REDIRECT := "stax://auth"

var access_token : String = ""
var _verifier    : String = ""
var _provider    : String = ""

func _ready() -> void:
	set_process(false)   # only poll the native auth bridge while a sign-in is in flight
	# Resume a stored session on launch (silent — never errors out a guest)
	if GameState.auth_refresh_token != "":
		_refresh(GameState.auth_refresh_token)
	_check_launch_args()

# ── Native in-app auth bridge (ASWebAuthenticationSession via WebAuth.m) ────────
# begin_sign_in writes the authorize URL to a file the native side polls; the native
# ASWebAuthenticationSession sheet handles sign-in in-app and writes the stax://auth
# callback URL back, which we poll for and feed to handle_redirect (no browser, no paste).
func _bridge_dir() -> String:
	var ud := OS.get_user_data_dir()
	for marker in ["/Library/", "/Documents/"]:
		var i := ud.find(marker)
		if i > 0:
			return ud.substr(0, i) + "/Documents"
	return ud

func _start_web_auth(url: String) -> void:
	var f := FileAccess.open(_bridge_dir() + "/_webauth_req.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(url)
		f = null
		set_process(true)
	else:
		OS.shell_open(url)   # fallback if the bridge dir isn't writable

func _process(_delta: float) -> void:
	var p := _bridge_dir() + "/_webauth_res.txt"
	if not FileAccess.file_exists(p):
		return
	set_process(false)
	var res := ""
	var f := FileAccess.open(p, FileAccess.READ)
	if f != null:
		res = f.get_as_text().strip_edges()
		f = null
	DirAccess.remove_absolute(p)
	if res == "" or res.begins_with("ERR"):
		_verifier = ""
		sign_in_failed.emit("cancelled")
	else:
		handle_redirect(res)

func is_signed_in() -> bool:
	return access_token != "" or GameState.auth_refresh_token != ""

# ── Start sign-in (opens the browser) ────────────────────────────────────────
func begin_sign_in(provider: String) -> void:
	if not Net.is_configured():
		sign_in_failed.emit("offline")
		return
	_provider = provider
	_verifier = _rand_verifier()
	var challenge := _b64url(_sha256(_verifier))
	var url := Net.SUPABASE_URL + "/auth/v1/authorize?provider=" + provider \
		+ "&redirect_to=" + AUTH_REDIRECT.uri_encode() \
		+ "&code_challenge=" + challenge \
		+ "&code_challenge_method=S256"
	_start_web_auth(url)

# Accepts the full redirect URL (deep link) OR just the pasted code.
func handle_redirect(url_or_code: String) -> void:
	# OAuth error came back in the redirect (e.g. provider declined) — surface it.
	if "error=" in url_or_code and "code=" not in url_or_code:
		var e := url_or_code.get_slice("error=", 1).get_slice("&", 0)
		var d := ""
		if "error_description=" in url_or_code:
			d = ": " + url_or_code.get_slice("error_description=", 1).get_slice("&", 0).uri_decode()
		_verifier = ""
		sign_in_failed.emit("oauth: " + e.uri_decode() + d)
		return
	var code := url_or_code
	if "code=" in url_or_code:
		code = url_or_code.get_slice("code=", 1).get_slice("&", 0)
	complete_with_code(code.strip_edges().uri_decode())

func complete_with_code(code: String) -> void:
	if code == "":
		sign_in_failed.emit("no code")
		return
	if _verifier == "":
		sign_in_failed.emit("session expired — start sign in again")
		return
	_post_auth("token?grant_type=pkce", {"auth_code": code, "code_verifier": _verifier},
		func(ok: bool, res: Variant): _on_session(ok, res, false))

func sign_out() -> void:
	access_token = ""
	GameState.clear_auth()
	signed_out.emit()

# ── Session ────────────────────────────────────────────────────────────────────
func _refresh(rt: String) -> void:
	_post_auth("token?grant_type=refresh_token", {"refresh_token": rt},
		func(ok: bool, res: Variant): _on_session(ok, res, true))

func _on_session(ok: bool, res: Variant, silent: bool) -> void:
	if not ok or typeof(res) != TYPE_DICTIONARY or not (res as Dictionary).has("access_token"):
		if not silent:
			var detail := ""
			if typeof(res) == TYPE_DICTIONARY:
				var rd := res as Dictionary
				detail = str(rd.get("error_description", rd.get("error_code", rd.get("msg", rd.get("error", "")))))
			sign_in_failed.emit("sign-in failed" + ("" if detail == "" else ": " + detail))
		return
	var d := res as Dictionary
	access_token = str(d["access_token"])
	if d.has("refresh_token"):
		GameState.set_auth(str(d["refresh_token"]), _provider)
	_verifier = ""
	_sync_profile()

# Link (first sign-in → claim guest progress) or fetch (reinstall → restore), merge both ways.
func _sync_profile() -> void:
	_post_rpc("link_or_get_profile", {
		"p_player_id": GameState.player_id,
		"p_friend_code": GameState.friend_code,
		"p_data": GameState.cloud_snapshot(),
	}, func(ok: bool, res: Variant):
		if not ok or typeof(res) != TYPE_DICTIONARY:
			sign_in_failed.emit("profile sync failed")
			return
		var d := res as Dictionary
		var existed := bool(d.get("existed", false))
		if existed:
			# Reinstall / another device: adopt the account's durable id + merge its data
			GameState.adopt_account(str(d.get("player_id", "")), str(d.get("friend_code", "")))
			var data : Variant = d.get("data", {})
			if data is Dictionary:
				GameState.apply_cloud_profile(data)
			# Push the merged union back up so the server has the latest
			_post_rpc("push_profile",
				{"p_data": GameState.cloud_snapshot(), "p_friend_code": GameState.friend_code},
				Callable())
		GameState._sync_online()   # refresh the leaderboard row under the durable id
		signed_in.emit(existed))

# Push the current snapshot up (call after notable progress while signed in).
func push_progress() -> void:
	if access_token == "":
		return
	_post_rpc("push_profile",
		{"p_data": GameState.cloud_snapshot(), "p_friend_code": GameState.friend_code}, Callable())

# ── HTTP ───────────────────────────────────────────────────────────────────────
func _post_auth(path: String, body: Dictionary, cb: Callable) -> void:
	_post(Net.SUPABASE_URL + "/auth/v1/" + path, PackedStringArray([
		"apikey: " + Net.SUPABASE_ANON_KEY, "Content-Type: application/json"]), body, cb)

func _post_rpc(fn: String, body: Dictionary, cb: Callable) -> void:
	_post(Net.SUPABASE_URL + "/rest/v1/rpc/" + fn, PackedStringArray([
		"apikey: " + Net.SUPABASE_ANON_KEY,
		"Authorization: Bearer " + access_token,
		"Content-Type: application/json"]), body, cb)

func _post(url: String, headers: PackedStringArray, body: Dictionary, cb: Callable) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 12.0
	http.request_completed.connect(
		func(_r: int, code: int, _h: PackedStringArray, data: PackedByteArray):
			http.queue_free()
			var parsed : Variant = null
			if data.size() > 0:
				parsed = JSON.parse_string(data.get_string_from_utf8())
			if cb.is_valid():
				cb.call(code >= 200 and code < 300, parsed))
	if http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		http.queue_free()
		if cb.is_valid():
			cb.call(false, null)

func _check_launch_args() -> void:
	for a : String in OS.get_cmdline_args():
		if a.begins_with("stax://") and "code=" in a:
			handle_redirect(a)
			return

# ── PKCE helpers ─────────────────────────────────────────────────────────────
func _rand_verifier() -> String:
	return _b64url(Crypto.new().generate_random_bytes(64))

func _sha256(s: String) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(s.to_utf8_buffer())
	return ctx.finish()

func _b64url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")
