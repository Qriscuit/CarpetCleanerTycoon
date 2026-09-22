shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, world_vertex_coords;

// INSTANCE_CUSTOM = (birth modulo 8 seconds, duration, rotation, active).
// One pooled horizontal quad supplies a short stylized crown/ring at impact.
uniform float water_clock = 0.0;
uniform vec4 splash_tint : source_color = vec4(0.43, 0.82, 0.92, 0.72);
varying float splash_age;
varying float splash_duration;
varying float splash_rotation;
varying float splash_active;

void vertex() {
	float duration = INSTANCE_CUSTOM.g;
	float age = mod(water_clock - INSTANCE_CUSTOM.r + 8.0, 8.0);
	splash_age = age;
	splash_duration = duration;
	splash_rotation = INSTANCE_CUSTOM.b;
	splash_active = INSTANCE_CUSTOM.a;
	vec3 center = MODEL_MATRIX[3].xyz;
	if (INSTANCE_CUSTOM.a < 0.5 || duration <= 0.0 || age >= duration) {
		VERTEX = center - vec3(0.0, 10.0, 0.0);
	} else {
		float t = clamp(age / duration, 0.0, 1.0);
		vec3 offset = VERTEX - center;
		offset *= mix(0.32, 1.08, 1.0 - pow(1.0 - t, 2.0));
		VERTEX = center + offset;
	}
}

void fragment() {
	float t = clamp(splash_age / max(splash_duration, 0.0001), 0.0, 1.0);
	vec2 point = UV * 2.0 - 1.0;
	float distance_from_center = length(point);
	float angle = atan(point.y, point.x) + splash_rotation;
	float crown = 0.80 + sin(angle * 7.0 + t * 5.0) * 0.10;
	float outer = 1.0 - smoothstep(crown - 0.08, crown + 0.08, distance_from_center);
	float inner_radius = mix(0.12, 0.60, t);
	float inner = smoothstep(inner_radius - 0.08, inner_radius + 0.08, distance_from_center);
	float ring = outer * inner;
	float center_flash = (1.0 - smoothstep(0.0, 0.34, distance_from_center)) * (1.0 - smoothstep(0.0, 0.28, t));
	float fade = 1.0 - smoothstep(0.58, 1.0, t);
	ALBEDO = splash_tint.rgb + vec3(0.18) * center_flash;
	ALPHA = (ring * 0.72 + center_flash * 0.52) * fade * splash_tint.a * splash_active;
}
