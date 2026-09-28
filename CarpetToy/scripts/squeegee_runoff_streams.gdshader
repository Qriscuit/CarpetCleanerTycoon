shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float water_clock = 0.0;
uniform float packet_lifetime = 2.50;
uniform float fade_start = 1.65;
uniform float cap_radius = 0.17;
uniform float floor_blend_start = 8.22;
uniform float floor_blend_end = 8.62;
uniform bool use_rug_surface = false;
uniform sampler2D rug_surface : filter_nearest, repeat_disable;
varying float flow_distance;
varying float flow_across;
varying float packet_fade;

float station_distance(float back_distance, float front_distance, float along) {
	float station = clamp(along, 0.0, 1.0) * 17.0;
	float cap = min(cap_radius, max(front_distance - back_distance, 0.0) * 0.5);
	if (station <= 4.0) {
		return back_distance + cap * (1.0 - cos(station / 4.0 * PI * 0.5));
	}
	if (station >= 13.0) {
		return front_distance - cap * (1.0 - cos((17.0 - station) / 4.0 * PI * 0.5));
	}
	return mix(back_distance + cap, front_distance - cap, (station - 4.0) / 9.0);
}

void vertex() {
	float front_distance = INSTANCE_CUSTOM.x;
	float back_distance = INSTANCE_CUSTOM.y;
	float width = INSTANCE_CUSTOM.z;
	float age = INSTANCE_CUSTOM.w * packet_lifetime;
	float lateral = UV.y * 2.0 - 1.0;
	flow_distance = station_distance(back_distance, front_distance, UV.x);
	flow_across = lateral;
	packet_fade = 1.0 - smoothstep(fade_start, packet_lifetime, age);
	float cap_length = min(cap_radius, max(front_distance - back_distance, 0.00001) * 0.5);
	float cap = clamp(min(flow_distance - back_distance, front_distance - flow_distance) / cap_length, 0.0, 1.0);
	float round_cap = sqrt(max(0.0, cap * (2.0 - cap)));
	float ripple = 1.0 + 0.07 * sin(flow_distance * 4.4 - water_clock * 5.4 + MODEL_MATRIX[3].x * 1.9 + MODEL_MATRIX[3].z * 0.8);
	float half_width = width * 0.5 * round_cap * sqrt(packet_fade) * mix(0.82, 1.0, sqrt(COLOR.r)) * ripple;
	float bend = (COLOR.g * 0.24 - 0.12) * sin(flow_distance * 0.85) * smoothstep(0.0, 0.45, flow_distance);
	vec3 local_point = vec3(bend + lateral * half_width, 0.0, flow_distance);
	vec3 world_point = (MODEL_MATRIX * vec4(local_point, 1.0)).xyz;
	// Delay descent until a complete strip interval has passed the tile edge;
	// lowering the first outside vertex immediately clips the preceding span.
	float floor_distance = max(abs(world_point.x), abs(world_point.z));
	float support = mix(0.006, -0.029, smoothstep(floor_blend_start, floor_blend_end, floor_distance));
	if (use_rug_surface) {
		vec2 surface_uv = world_point.xz / vec2(2.0, 3.32) + 0.5;
		bool within = all(greaterThanEqual(surface_uv, vec2(0.0))) && all(lessThanEqual(surface_uv, vec2(1.0)));
		if (within && textureLod(rug_surface, surface_uv, 0.0).r > 0.5) { support = 0.071; }
	}
	float dome = (1.0 - lateral * lateral) * 0.010 * packet_fade;
	VERTEX = vec3(local_point.x, support - MODEL_MATRIX[3].y + 0.003 + dome, local_point.z);
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	if (packet_fade < 0.0002) { discard; }
	// Matte, flat-color flow accents. No white rim, shiny crest or refraction.
	float centered = 1.0 - smoothstep(0.30, 0.94, abs(flow_across));
	float moving_band = sin(flow_distance * 5.0 - water_clock * 26.0 + flow_across * 1.1);
	float accent = smoothstep(0.35, 0.94, moving_band) * centered * 0.55;
	ALBEDO = mix(vec3(0.16, 0.69, 0.79), vec3(0.40, 0.84, 0.88), accent);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
