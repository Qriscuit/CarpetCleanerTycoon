shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 grid_points[112];
uniform vec3 fallback_forward = vec3(0.0, 0.0, -1.0);
uniform float water_clock = 0.0;
uniform float ripple_height = 0.006;
uniform sampler2D rug_surface : filter_nearest, repeat_disable;
varying vec3 world_point;
varying float side_face;

void vertex() {
	int lane = int(round(UV.x * 6.0));
	int row = int(round(UV.y * 15.0));
	vec4 point = grid_points[row * 7 + lane];
	vec3 across = grid_points[row * 7 + min(lane + 1, 6)].xyz - grid_points[row * 7 + max(lane - 1, 0)].xyz;
	across = length(across) > 0.0001 ? normalize(across) : normalize(cross(vec3(0,1,0), fallback_forward));
	vec3 tangent = grid_points[min(row + 1, 15) * 7 + lane].xyz - grid_points[max(row - 1, 0) * 7 + lane].xyz;
	tangent = length(tangent) > 0.0001 ? normalize(tangent) : fallback_forward;
	vec3 up = normalize(cross(tangent, across));
	if (up.y < 0.0) { up = -up; }
	float envelope = sin(UV.y * 3.14159265) * smoothstep(0.002, 0.012, point.w);
	float ripple = sin(UV.y * 15.0 - water_clock * 8.0 + UV.x * 4.0) * ripple_height * envelope;
	float edge = (UV.x - 0.5) * sin(UV.y * 19.0 - water_clock * 6.0) * 0.009 * envelope;
	VERTEX = point.xyz + up * (UV2.x * point.w + ripple) + across * edge;
	side_face = abs(NORMAL.x) + abs(NORMAL.z);
	NORMAL = normalize(across * NORMAL.x + up * NORMAL.y + tangent * NORMAL.z);
	world_point = VERTEX;
}

void fragment() {
	vec2 rug_uv = world_point.xz / vec2(2.0, 3.32) + 0.5;
	bool within = all(greaterThanEqual(rug_uv, vec2(0))) && all(lessThanEqual(rug_uv, vec2(1)));
	float plane = within && texture(rug_surface, rug_uv).r > 0.5 ? 0.071 : 0.006;
	if (world_point.y < plane - 0.004) { discard; }
	vec3 cyan = vec3(0.14, 0.68, 0.76);
	vec3 mint = vec3(0.37, 0.87, 0.87);
	float edge_light = pow(abs(UV.x * 2.0 - 1.0), 9.0);
	float streak = exp(-pow((UV.x - 0.24 - 0.025 * sin(UV.y * 6.0 - water_clock * 2.0)) / 0.035, 2.0));
	streak *= smoothstep(0.05, 0.20, UV.y) * (1.0 - smoothstep(0.78, 1.0, UV.y));
	float flow = 0.5 + 0.5 * sin(UV.y * 12.0 - water_clock * 6.0 + UV.x * 1.6);
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 3.0);
	vec3 color = mix(cyan, mint, 0.26 + flow * 0.16 + edge_light * 0.26);
	color *= 1.0 - side_face * 0.16;
	ALBEDO = mix(color, vec3(0.78, 0.98, 0.96), streak * 0.55 + rim * 0.12);
	ROUGHNESS = 0.28;
}
