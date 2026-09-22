shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float water_clock = 0.0;
uniform sampler2D rug_surface : filter_nearest, repeat_disable;
uniform vec4 landing_points[21];
uniform vec4 landing_sides[3];
varying vec3 world_point;
varying float rug_landing;
varying float fullness;

void vertex() {
	int segment = int(round(INSTANCE_CUSTOM.x));
	rug_landing = INSTANCE_CUSTOM.y;
	float lane = UV.x * 7.0 - 0.5;
	int left = int(floor(clamp(lane, 0.0, 6.0)));
	int right = min(left + 1, 6);
	vec4 point = mix(landing_points[segment * 7 + left], landing_points[segment * 7 + right], fract(clamp(lane, 0.0, 6.0)));
	vec3 side = landing_sides[segment].xyz;
	vec3 forward = cross(side, vec3(0,1,0));
	point.xyz += side * landing_sides[segment].w * (lane - clamp(lane, 0.0, 6.0));
	fullness = point.w;
	float round_end = sqrt(max(0.0, 1.0 - pow(abs(UV.x * 2.0 - 1.0), 12.0)));
	float scallop = 1.0 + 0.075 * sin(UV.x * 26.0 + water_clock * 3.8) + 0.045 * sin(UV.x * 43.0 - water_clock * 2.0);
	float depth = (UV.y * 2.0 - 1.0) * 0.15 * round_end * scallop * fullness;
	float crown = exp(-pow((UV.y - 0.78) / 0.17, 2.0));
	VERTEX = point.xyz + forward * (0.045 + depth);
	VERTEX.y = mix(0.009, 0.074, rug_landing) + (0.003 + crown * (0.017 + 0.008 * sin(UV.x * 25.0 - water_clock * 4.0))) * fullness * round_end;
	world_point = VERTEX;
}

void fragment() {
	vec2 rug_uv = world_point.xz / vec2(2.0, 3.32) + 0.5;
	bool within = all(greaterThanEqual(rug_uv, vec2(0))) && all(lessThanEqual(rug_uv, vec2(1)));
	bool on_rug = within && texture(rug_surface, rug_uv).r > 0.5;
	if (on_rug != (rug_landing > 0.5) || fullness < 0.01) { discard; }
	float rim = smoothstep(0.68, 0.86, UV.y) * (1.0 - smoothstep(0.92, 1.0, UV.y));
	float glint = 0.5 + 0.5 * sin(UV.x * 13.0 + water_clock * 3.0);
	ALBEDO = mix(vec3(0.20, 0.76, 0.81), vec3(0.72, 0.98, 0.94), rim * (0.42 + 0.20 * glint));
	ROUGHNESS = 0.28;
}
