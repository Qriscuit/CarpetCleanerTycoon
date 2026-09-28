shader_type spatial;
render_mode unshaded, cull_disabled;

// The same open-center strip fits a hose circle or rounded blade.
// No transparent overdraw, screen sampling, filled disk, or airborne column.
uniform float water_clock = 0.0;
uniform bool rectangular = false;
uniform float impact_radius = 0.17;
uniform vec2 half_extents = vec2(0.34, 0.075);
uniform float corner_radius = 0.0225;
uniform float perimeter_length = 1.6;
uniform float lobe_count = 14.0;
uniform float outward_reach = 0.17;
uniform float crest_height = 0.085;
uniform float strength = 1.0;
uniform bool use_rug_surface = false;
uniform sampler2D rug_surface : filter_nearest, repeat_disable;
uniform vec4 water_tint : source_color = vec4(0.20, 0.76, 0.83, 1.0);
// Optional pooled, world-anchored extraction contour. False preserves the
// existing circular hose and four-sided head splash path exactly.
uniform bool trail_mode = false;
uniform float trail_reach = 0.080;
uniform float spill_reach = 0.220;
uniform float runoff_outward_travel = 0.08;
uniform float trail_min_crest = 0.035;
uniform float trail_max_crest = 0.090;
varying float crest;
varying float pulse;
varying float trail_spill;
varying float trail_drain;

vec4 corner_frame(vec2 center, float angle, float radius) {
	vec2 outward = vec2(cos(angle), sin(angle));
	return vec4(center + outward * radius, outward);
}

vec4 perimeter_frame(float fraction) {
	if (!rectangular) {
		vec2 outward = vec2(cos(fraction * TAU), sin(fraction * TAU));
		return vec4(outward * impact_radius, outward);
	}
	float a = half_extents.x;
	float b = half_extents.y;
	float r = corner_radius;
	float horizontal = 2.0 * (a - r);
	float vertical = 2.0 * (b - r);
	float arc = PI * 0.5 * r;
	float distance = fract(fraction) * perimeter_length;
	if (distance < horizontal) { return vec4(a - r - distance, b, 0.0, 1.0); }
	distance -= horizontal;
	if (distance < arc) { return corner_frame(vec2(-a + r, b - r), PI * 0.5 + distance / r, r); }
	distance -= arc;
	if (distance < vertical) { return vec4(-a, b - r - distance, -1.0, 0.0); }
	distance -= vertical;
	if (distance < arc) { return corner_frame(vec2(-a + r, -b + r), PI + distance / r, r); }
	distance -= arc;
	if (distance < horizontal) { return vec4(-a + r + distance, -b, 0.0, -1.0); }
	distance -= horizontal;
	if (distance < arc) { return corner_frame(vec2(a - r, -b + r), PI * 1.5 + distance / r, r); }
	distance -= arc;
	if (distance < vertical) { return vec4(a, -b + r + distance, 1.0, 0.0); }
	distance -= vertical;
	return corner_frame(vec2(a - r, b - r), distance / r, r);
}

void vertex() {
	if (trail_mode) {
		float along = UV.x;
		float across = UV.y;
		vec2 normal_a = vec2(cos(INSTANCE_CUSTOM.x), sin(INSTANCE_CUSTOM.x));
		vec2 normal_b = vec2(cos(INSTANCE_CUSTOM.y), sin(INSTANCE_CUSTOM.y));
		vec2 outward = normalize(mix(normal_a, normal_b, along));
		float spill_a = mod(round(INSTANCE_CUSTOM.z), 2.0);
		float spill_b = floor(round(INSTANCE_CUSTOM.z) * 0.5);
		float spill = mix(spill_a, spill_b, along);
		// Instance colors contain only normalized endpoint ages, not tint. These
		// remain precise in Compatibility without packing a large timestamp.
		trail_spill = spill;
		trail_drain = mix(COLOR.r, COLOR.g, along);
		float runoff_amount = 1.0 - smoothstep(0.0, 1.0, trail_drain);
		float pressure_a = mod(round(INSTANCE_CUSTOM.w), 32.0) / 31.0;
		float pressure_b = floor(round(INSTANCE_CUSTOM.w) / 32.0) / 31.0;
		float pressure = mix(pressure_a, pressure_b, along);
		vec3 world_base = (MODEL_MATRIX * vec4(along - 0.5, 0.0, 0.0, 1.0)).xyz;
		float phase = world_base.x * 32.0 + world_base.z * 47.0 - water_clock * 3.8;
		pulse = 0.5 + 0.5 * sin(phase);
		float profile = 1.0 - cos(across * PI * 0.5);
		float ridge_distance = -0.008 + trail_reach * (0.78 + 0.22 * pulse) * strength * profile;
		float edge_wave = 0.5 + 0.5 * sin(world_base.x * 32.0 + world_base.z * 47.0);
		float front = spill_reach * (0.91 + 0.09 * edge_wave) + runoff_outward_travel * trail_drain;
		float back = mix(-0.008, front, smoothstep(0.0, 1.0, trail_drain));
		float runoff_distance = mix(back, front, profile);
		float distance = mix(ridge_distance, runoff_distance, spill);
		crest = pow(max(0.0, sin(across * PI)), 0.85);
		float ridge = mix(trail_min_crest, trail_max_crest, pressure) * (0.48 + 0.52 * pulse) * crest * strength;
		// Support follows the moving packet's WORLD distance. At expiry all
		// cross-rows reach the same floor point, not a residual vertical wall.
		float support = mix(0.071, 0.006, spill * smoothstep(0.006, 0.180, runoff_distance));
		float skirt = 0.010 * sin(across * PI) * (0.65 + 0.35 * pulse) * runoff_amount;
		float height = mix(ridge, skirt, spill);
		float segment_length = max(length(MODEL_MATRIX[0].xyz), 0.0001);
		vec3 sample_local = vec3(along - 0.5 + outward.x * distance / segment_length, 0.0, outward.y * distance);
		vec3 sample_world = (MODEL_MATRIX * vec4(sample_local, 1.0)).xyz;
		vec2 surface_uv = sample_world.xz / vec2(2.0, 3.32) + 0.5;
		bool within_surface = all(greaterThanEqual(surface_uv, vec2(0.0))) && all(lessThanEqual(surface_uv, vec2(1.0)));
		bool supported = within_surface && textureLod(rug_surface, surface_uv, 0.0).r > 0.5;
		if (supported) { support = max(support, 0.071); }
		VERTEX = vec3(along - 0.5 + outward.x * distance / segment_length,
			support - MODEL_MATRIX[3].y + 0.003 + height, outward.y * distance);
		NORMAL = normalize(vec3(-outward.x * cos(across * PI), 1.0, -outward.y * cos(across * PI)));
	} else {
	trail_spill = 0.0;
	trail_drain = 0.0;
	vec4 frame = perimeter_frame(UV.x);
	float phase = UV.x * TAU;
	float rhythmic_wave = 0.5 + 0.5 * sin(phase * lobe_count - water_clock * 5.0);
	float swell = 0.82 + 0.18 * sin(phase * 3.0 + water_clock * 2.4);
	pulse = rhythmic_wave * swell;
	float extension = outward_reach * (0.72 + 0.28 * pulse) * strength;
	float across = UV.y;
	// Steep lift at the root turns outward, then falls to the contact apron.
	// Perimeter phases form short, dancing scallops instead of flying sheets.
	float distance = -0.008 + extension * (1.0 - cos(across * PI * 0.5));
	crest = pow(max(0.0, sin(across * PI)), 0.85);
	float height = crest_height * (0.43 + 0.57 * pulse) * crest * strength;
	vec2 planar_point = frame.xy + frame.zw * distance;
	vec3 world_point = (MODEL_MATRIX * vec4(planar_point.x, 0.0, planar_point.y, 1.0)).xyz;
	float support = MODEL_MATRIX[3].y;
	if (use_rug_surface) {
		vec2 rug_uv = world_point.xz / vec2(2.0, 3.32) + 0.5;
		bool within = all(greaterThanEqual(rug_uv, vec2(0.0))) && all(lessThanEqual(rug_uv, vec2(1.0)));
		bool on_rug = within && textureLod(rug_surface, rug_uv, 0.0).r > 0.5;
		support = on_rug ? 0.071 : 0.006;
	}
	VERTEX = vec3(planar_point.x, support - MODEL_MATRIX[3].y + 0.003 + height, planar_point.y);
	// Each straight side uses its true perpendicular, not a center-radial normal.
	float slope = cos(across * PI) * 1.8 * (0.43 + 0.57 * pulse);
	NORMAL = normalize(vec3(-frame.z * slope, 1.0, -frame.w * slope));
	}
}

void fragment() {
	// Local runoff must disappear even when another stroke keeps the carpet
	// ridge globally alive. Opaque discard removes every expired apron pixel.
	if (trail_mode && trail_spill > 0.001 && trail_drain >= 0.999) { discard; }
	float pale_crest = smoothstep(0.78, 0.98, crest) * (0.48 + 0.24 * pulse);
	float lip = smoothstep(0.82, 0.91, UV.y) * (1.0 - smoothstep(0.95, 1.0, UV.y));
	vec3 base = water_tint.rgb * mix(0.90, 1.0, crest);
	ALBEDO = mix(base, vec3(0.72, 0.97, 0.96), max(pale_crest, lip * 0.28));
	ROUGHNESS = 0.27;
	SPECULAR = 0.65;
	EMISSION = water_tint.rgb * 0.06;
}
