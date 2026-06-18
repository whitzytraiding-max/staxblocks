extends Node

# Procedural sound effects — all audio is synthesized at startup,
# no asset files. 16-bit mono WAV buffers played through a small
# pool of AudioStreamPlayers so overlapping sounds don't cut off.

const RATE        := 22050
const MRATE       := 11025   # music renders at half rate — warmer, lofi, 2x faster to generate
const POOL_SIZE   := 6

var _pool         : Array[AudioStreamPlayer] = []
var _music_player : AudioStreamPlayer
var _music_task   : int = -1   # WorkerThreadPool task id for the async music render

var _snd_place    : AudioStreamWAV
var _snd_pickup   : AudioStreamWAV
var _snd_invalid  : AudioStreamWAV
var _snd_click    : AudioStreamWAV
var _snd_tick     : AudioStreamWAV
var _snd_combo    : AudioStreamWAV
var _snd_over     : AudioStreamWAV
var _snd_theme    : AudioStreamWAV
var _snd_board    : AudioStreamWAV
var _snd_best     : AudioStreamWAV
var _snd_kchirp   : AudioStreamWAV   # cat mode: short kitten "mrp" on placement
var _snd_kmeows   : Array = []       # cat mode: cute kitten meows (clears / unlock)
var _snd_clears   : Array = []   # indexed by lines cleared (1..5)

func _ready() -> void:
	for _i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.volume_db = -6.0
		add_child(p)
		_pool.append(p)

	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = -14.0
	add_child(_music_player)

	_build_sounds()
	# Music is ~29s of synthesis — render it off the main thread so the app starts
	# instantly; it begins playing a moment later when ready. WorkerThreadPool (not a
	# raw Thread) is engine-managed, which avoids the mobile teardown crash a manually
	# joined Thread could cause when iOS terminates the app.
	_music_task = WorkerThreadPool.add_task(_generate_music)

func _generate_music() -> void:
	var stream := _build_music()
	call_deferred("_on_music_ready", stream)

func _on_music_ready(stream: AudioStreamWAV) -> void:
	if not is_instance_valid(_music_player):
		return   # app is tearing down — don't touch a freed node
	_music_player.stream = stream
	update_music()

func _exit_tree() -> void:
	# Let the render task finish before this node is freed (its callable binds self).
	if _music_task != -1:
		WorkerThreadPool.wait_for_task_completion(_music_task)
		_music_task = -1

# ── Public API ────────────────────────────────────────────────────────────────
# In cat mode, placement + clears speak in little kitten meows
func play_place() -> void:
	if GameState.cat_mode: _play(_snd_kchirp)
	else: _play(_snd_place)
func play_pickup() -> void:  _play(_snd_pickup)
func play_invalid() -> void: _play(_snd_invalid)
func play_click() -> void:   _play(_snd_click)
func play_tick() -> void:    _play(_snd_tick)
func play_game_over() -> void: _play(_snd_over)
func play_theme() -> void:   _play(_snd_theme)
func play_board_clear() -> void: _play(_snd_board)
func play_best() -> void:    _play(_snd_best)
func play_meow() -> void:    _play(_snd_kmeows[randi() % _snd_kmeows.size()])

func play_clear(lines: int) -> void:
	if lines <= 0:
		return
	if GameState.cat_mode:
		_play(_snd_kmeows[randi() % _snd_kmeows.size()])
	else:
		_play(_snd_clears[clampi(lines, 1, 5) - 1])

func play_combo(n: int) -> void:
	if n >= 2:
		_play(_snd_combo)

func update_music() -> void:
	if _music_player.stream == null:
		return   # still rendering on the worker thread
	if GameState.music_on:
		if not _music_player.playing:
			_music_player.play()
	else:
		_music_player.stop()

# ── Playback ──────────────────────────────────────────────────────────────────
func _play(stream: AudioStreamWAV) -> void:
	if not GameState.sound_on or stream == null:
		return
	for p in _pool:
		if not p.playing:
			p.stream = stream
			p.play()
			return
	_pool[0].stream = stream
	_pool[0].play()

# ── Synthesis ─────────────────────────────────────────────────────────────────
func _build_sounds() -> void:
	# Soft bubbly pop on placement
	_snd_place   = _make_stream(_tone(480.0, 220.0, 0.09, 0.50))
	# Tiny up-blip when grabbing a piece
	_snd_pickup  = _make_stream(_tone(300.0, 520.0, 0.06, 0.30))
	# Low dull buzz for invalid drop
	_snd_invalid = _make_stream(_tone(160.0, 110.0, 0.14, 0.40, 0.55))
	# UI click (button release)
	_snd_click   = _make_stream(_tone(700.0, 500.0, 0.05, 0.35))
	# Soft low tick when a button pushes in (button down)
	_snd_tick    = _make_stream(_tone(320.0, 240.0, 0.04, 0.28))

	# Clear arpeggios — more lines = more notes, higher pitch
	var scale_notes := [523.25, 659.25, 783.99, 1046.5, 1318.5, 1568.0, 2093.0]
	for lines in range(1, 6):
		var buf := PackedByteArray()
		var count : int = 2 + lines
		for i in count:
			var f : float = scale_notes[mini(i + lines - 1, scale_notes.size() - 1)]
			buf.append_array(_tone(f, f * 1.02, 0.085, 0.45))
		_snd_clears.append(_make_stream(buf))

	# Combo sparkle — fast high triad
	var cb := PackedByteArray()
	for f in [1046.5, 1318.5, 1568.0]:
		cb.append_array(_tone(f, f, 0.06, 0.38))
	_snd_combo = _make_stream(cb)

	# Game over — sad descending walk
	var go := PackedByteArray()
	for f in [392.0, 329.63, 261.63, 196.0]:
		go.append_array(_tone(f, f * 0.97, 0.22, 0.42))
	_snd_over = _make_stream(go)

	# Theme change — rising shimmer sweep
	_snd_theme = _make_stream(_tone(400.0, 1600.0, 0.35, 0.30))

	# Board clear — triumphant fanfare
	var bc := PackedByteArray()
	for f in [523.25, 659.25, 783.99, 1046.5, 1046.5]:
		bc.append_array(_tone(f, f, 0.11, 0.45))
	_snd_board = _make_stream(bc)

	# New best — rising twinkle
	var nb := PackedByteArray()
	for f in [659.25, 830.61, 1046.5, 1318.5, 1661.2]:
		nb.append_array(_tone(f, f * 1.01, 0.09, 0.40))
	_snd_best = _make_stream(nb)

	# Kitten "mrp" chirp — very short, high, for placing a piece in cat mode
	var kc := PackedByteArray()
	kc.append_array(_tone(900.0, 1280.0, 0.07, 0.30, 0.85))
	_snd_kchirp = _make_stream(kc)

	# Kitten meows — high, cute rise-then-fall warbles (clears + the unlock)
	_snd_kmeows = []
	for base in [820.0, 940.0, 1060.0]:
		var km := PackedByteArray()
		km.append_array(_tone(base, base * 1.55, 0.10, 0.40, 0.85))
		km.append_array(_tone(base * 1.55, base * 0.80, 0.18, 0.40, 0.85))
		_snd_kmeows.append(_make_stream(km))

# ── Music — chill lofi loop (~29s) ────────────────────────────────────────────
# Am7 → Fmaj7 → Cmaj7 → G, twice through with two arpeggio patterns.
# Three layers per chord: soft sine pad (slow swell), warm sub bass, and a
# gentle bell arpeggio an octave up. Rendered at 11 kHz for a lofi warmth
# and generated on a worker thread (see _ready).
func _build_music() -> AudioStreamWAV:
	var prog := [
		{"bass": 110.00, "pad": [220.00, 261.63, 329.63, 392.00]},  # Am7
		{"bass":  87.31, "pad": [174.61, 220.00, 261.63, 329.63]},  # Fmaj7
		{"bass": 130.81, "pad": [196.00, 261.63, 329.63, 493.88]},  # Cmaj7
		{"bass":  98.00, "pad": [196.00, 246.94, 293.66, 392.00]},  # G
	]
	var patterns := [[0, 2, 1, 3, 2, 1, 2, 0], [3, 1, 2, 0, 1, 2, 1, 3]]
	const CHORD_DUR := 3.6
	const ARP_DUR   := CHORD_DUR / 8.0

	var buf := PackedByteArray()
	for rep in 2:
		var pattern : Array = patterns[rep]
		for chord in prog:
			var n   := int(CHORD_DUR * MRATE)
			var out := PackedByteArray()
			out.resize(n * 2)
			var pad  : Array = chord["pad"]
			var bass : float = chord["bass"]
			for i in n:
				var t := float(i) / float(MRATE)
				# Pad — slow swell in and out across the chord
				var env_pad := minf(t / 1.1, 1.0) * clampf((CHORD_DUR - t) / 1.4, 0.0, 1.0)
				var v := 0.0
				for f in pad:
					v += sin(TAU * f * t) * 0.085
				v *= env_pad
				# Sub bass — soft attack, gentle fade
				var env_bass := minf(t / 0.15, 1.0) * clampf((CHORD_DUR - t) / 1.0, 0.0, 1.0)
				v += sin(TAU * bass * t) * 0.26 * env_bass
				# Bell arpeggio — one note per eighth, octave up, quick decay
				var arp_i  := int(t / ARP_DUR)
				var at     := t - float(arp_i) * ARP_DUR
				var arp_f  : float = pad[pattern[arp_i % 8]] * 2.0
				var env_arp := minf(at / 0.02, 1.0) * pow(clampf(1.0 - at / ARP_DUR, 0.0, 1.0), 2.0)
				v += sin(TAU * arp_f * at) * 0.16 * env_arp
				out.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
			buf.append_array(out)

	var s := AudioStreamWAV.new()
	s.format     = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate   = MRATE
	s.stereo     = false
	s.data       = buf
	s.loop_mode  = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end   = buf.size() / 2
	return s

func _tone(freq_a: float, freq_b: float, dur: float, vol: float, sine_mix: float = 1.0) -> PackedByteArray:
	var n   := int(dur * RATE)
	var out := PackedByteArray()
	out.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		phase += TAU * lerpf(freq_a, freq_b, t) / RATE
		var env := minf(t / 0.04, 1.0) * (1.0 - t) * (1.0 - t)
		var s   := sin(phase)
		var sq  := 1.0 if s > 0.0 else -1.0
		var v   := (s * sine_mix + sq * (1.0 - sine_mix)) * env * vol
		out.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	return out

func _make_stream(data: PackedByteArray) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format   = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo   = false
	s.data     = data
	return s
