shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D clean_map : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 clean_color : source_color = vec4(1.0);
uniform vec4 surface_tint : source_color = vec4(1.0);
uniform sampler2D soil_map : source_color, filter_linear_mipmap;
uniform sampler2D coverage : filter_linear, repeat_disable, hint_default_white;
// Prototype feel controls: retain the pattern under a pale, warm dust veil.
uniform float dust_strength : hint_range(0.0, 1.0) = 0.58;
uniform vec4 dust_tint : source_color = vec4(0.86, 0.79, 0.67, 1.0);
uniform vec3 rug_origin = vec3(0.0);
varying vec2 rug_uv;

void vertex() {
	vec3 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - rug_origin;
	rug_uv = vec2(p.x / 2.0 + 0.5, p.z / 3.32 + 0.5);
}

void fragment() {
	float soil = texture(coverage, rug_uv).r;
	vec3 clean = texture(clean_map, UV).rgb * clean_color.rgb * surface_tint.rgb;
	vec3 pale_dust = mix(texture(soil_map, rug_uv).rgb, dust_tint.rgb, 0.70);
	ALBEDO = mix(clean, pale_dust, soil * dust_strength);
	ROUGHNESS = 0.96;
	SPECULAR = 0.12;
}
