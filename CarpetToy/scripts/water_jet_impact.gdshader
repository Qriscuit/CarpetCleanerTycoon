shader_type spatial;
render_mode unshaded, cull_disabled;

// One permanent radial mesh. Opaque geometry gives the contact a readable,
// shallow crown without transparent layers or screen-space water rendering.
uniform float water_clock = 0.0;
uniform float impact_radius = 0.17;
uniform float strength = 1.0;
uniform vec4 water_tint : source_color = vec4(0.20, 0.76, 0.83, 1.0);
varying float ring_position;
varying float crown_height;

void vertex() {
	float angle = UV.x;
	float radial = UV.y;
	float wave = sin(angle * 5.0 + water_clock * 7.0) * 0.075
		+ sin(angle * 9.0 - water_clock * 5.0) * 0.035;
	float scallop = 1.0 + wave * smoothstep(0.25, 1.0, radial);
	float radius = impact_radius * radial * scallop * strength;
	float crest_offset = (radial - 0.88) * 9.0;
	float crest = exp(-crest_offset * crest_offset);
	float edge_lobes = 0.65 + 0.35 * sin(angle * 7.0 + water_clock * 8.0);
	float height = impact_radius * strength * (0.012 + crest * 0.20 * edge_lobes);
	VERTEX = vec3(cos(angle) * radius, height, sin(angle) * radius);
	// The crown has a soft radial normal, avoiding a flat cardboard highlight.
	float slope = crest * (radial - 0.88) * 14.0 * edge_lobes;
	NORMAL = normalize(vec3(cos(angle) * slope, 1.0, sin(angle) * slope));
	ring_position = radial;
	crown_height = crest;
}

void fragment() {
	float crest_glint = smoothstep(0.45, 0.95, crown_height) * 0.5;
	float center_glint = (1.0 - smoothstep(0.0, 0.30, ring_position)) * 0.20;
	ALBEDO = mix(water_tint.rgb, vec3(0.63, 0.92, 0.97), crest_glint + center_glint);
	ROUGHNESS = 0.24;
	SPECULAR = 0.70;
	EMISSION = water_tint.rgb * 0.10;
}
