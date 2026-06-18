// Animated board border, tinted to the active biome's colour.
// A rounded-rectangle signed-distance field gives smooth, anti-aliased corners.
// A wave of light flows around the rim — bright highlights travelling through the
// biome colour (RGB-LED style: nothing physically moves, the shade cycles).
// `u_pulse` flares it on clears. Runs on the GPU via TIME, so no per-frame CPU.
shader_type canvas_item;

uniform float u_pulse = 0.0;          // 0..1.5 clear flare (set from GDScript)
uniform vec2  u_size = vec2(446.0);   // ColorRect size in px
uniform float u_half = 189.0;         // half-extent from centre to the rim
uniform float u_radius = 16.0;        // corner radius px
uniform float u_thickness = 3.0;      // rim half-thickness px
uniform vec3  u_col = vec3(0.6, 0.8, 1.0);  // biome accent colour (set from GDScript)
uniform float u_wraps = 3.0;          // highlights around the ring — keep INTEGER so the pattern meets itself at the atan2 seam (no split)
uniform float u_speed = 0.45;         // flow speed

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

void fragment() {
	vec2 p = (UV - 0.5) * u_size;                 // centred pixel coords
	float d = sd_round_box(p, vec2(u_half), u_radius);

	float ang = atan(p.y, p.x) / 6.2831853 + 0.5; // 0..1 around the perimeter
	float wave = 0.5 + 0.5 * sin((ang * u_wraps - TIME * u_speed) * 6.2831853);
	// Stay in the biome's colour family: deep shade → bright, white-tipped highlight
	vec3 dim = u_col * 0.42;
	vec3 hot = mix(u_col, vec3(1.0), 0.30);
	vec3 col = mix(dim, hot, wave);

	float th = u_thickness * (1.0 + u_pulse * 0.5);
	// Rim drawn outward only — multiplying by smoothstep(-th, 0, d) fades it
	// to zero before it reaches the board interior, so blocks aren't covered.
	float rim = (1.0 - smoothstep(th, th + 2.0, abs(d))) * smoothstep(-th, 0.0, d);
	// Outward glow only (d>0), blooms on a clear
	float glow = exp(-max(d, 0.0) * 0.07) * step(0.0, d) * (0.30 + u_pulse * 0.65);

	float a = clamp(rim + glow * 0.7, 0.0, 1.0);
	COLOR = vec4(col, a);
}
