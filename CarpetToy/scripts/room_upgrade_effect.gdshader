shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float opacity : hint_range(0.0, 1.0) = 0.0;
uniform float phase : hint_range(0.0, 1.0) = 0.0;
uniform bool ring_mode = false;
varying float pillar_height;

void vertex() {
	pillar_height = clamp(VERTEX.y + 0.5, 0.0, 1.0);
	if (!ring_mode) {
		float wave = sin(phase * 9.42478 - pillar_height * 4.0);
		VERTEX.xz *= 1.0 + wave * 0.045 * pillar_height;
	}
}

void fragment() {
	float fade = ring_mode ? 1.0 : pow(1.0 - pillar_height, 1.65);
	ALBEDO = vec3(1.0);
	EMISSION = vec3(ring_mode ? 0.6 : fade * 0.9);
	ALPHA = opacity * fade;
}
