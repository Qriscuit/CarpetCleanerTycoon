shader_type spatial;
render_mode diffuse_burley, cull_disabled;

uniform sampler2D clean_map : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 clean_color : source_color = vec4(1.0);
uniform vec4 surface_tint : source_color = vec4(1.0);
uniform sampler2D soil_map : source_color, filter_linear_mipmap;
uniform sampler2D coverage : filter_linear, repeat_disable, hint_default_white;
// Prototype feel controls: retain the pattern under a pale, warm dust veil.
uniform float dust_strength : hint_range(0.0, 1.0) = 0.58;
uniform vec4 dust_tint : source_color = vec4(0.86, 0.79, 0.67, 1.0);
uniform vec3 rug_origin = vec3(0.0);
uniform vec3 roll_mesh_offset = vec3(0.0);
uniform bool roll_enabled = false;
uniform float roll_amount : hint_range(0.0, 1.0) = 0.0;
uniform float roll_direction = -1.0;
varying vec2 rug_uv;

void vertex() {
	// Use the undeformed rug coordinates: the weave travels with the roll.
	vec3 p = roll_enabled ? VERTEX + roll_mesh_offset : (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - rug_origin;
	rug_uv = vec2(p.x / 2.0 + 0.5, p.z / 3.32 + 0.5);
	float front = mix(1.72, -1.72, roll_amount);
	float distance = max(p.z * roll_direction - front, 0.0);
	if (roll_enabled && distance > 0.0 && roll_amount > 0.0) {
		// Wind into a spiral with room for the rug's thickness, rather than
		// overlapping several layers on the same cylinder.
		float radius = 0.17 + 0.22 * sqrt(roll_amount);
		float winding = 0.014;
		float angle = (radius - sqrt(max(radius * radius - 2.0 * winding * distance, 0.001))) / winding;
		float inner_radius = radius - winding * angle;
		float s = sin(angle);
		float c = cos(angle);
		float thickness = p.y;
		p.y = radius - (inner_radius - thickness) * c;
		p.z = (front + (inner_radius - thickness) * s) * roll_direction;
		float normal_z = NORMAL.z * roll_direction;
		NORMAL = vec3(NORMAL.x, NORMAL.y * c + normal_z * s, (-NORMAL.y * s + normal_z * c) * roll_direction);
		VERTEX = p - roll_mesh_offset;
	}
}

void fragment() {
	float soil = texture(coverage, rug_uv).r;
	vec3 clean = texture(clean_map, UV).rgb * clean_color.rgb * surface_tint.rgb;
	vec3 pale_dust = mix(texture(soil_map, rug_uv).rgb, dust_tint.rgb, 0.70);
	ALBEDO = mix(clean, pale_dust, soil * dust_strength);
	ROUGHNESS = 0.96;
	SPECULAR = 0.12;
}
