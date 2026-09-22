shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 ring_data[16];
uniform vec3 ring_sides[16];
uniform float water_clock = 0.0;
uniform vec4 water_tint : source_color = vec4(0.20, 0.76, 0.83, 1.0);
varying float axial;
varying float around;

void vertex() {
	int ring = clamp(int(round(UV.y * 15.0)), 0, 15);
	vec3 center = ring_data[ring].xyz;
	vec3 tangent = normalize(ring_data[min(ring + 1, 15)].xyz - ring_data[max(ring - 1, 0)].xyz + vec3(0.0, -0.000001, 0.0));
	vec3 side = normalize(ring_sides[ring]);
	vec3 binormal = normalize(cross(tangent, side));
	float angle = UV.x * 6.28318530718;
	vec3 radial = side * cos(angle) + binormal * sin(angle);
	float envelope = smoothstep(0.0, 0.14, UV.y);
	float ripple = 1.0 + envelope * (0.045 * sin(UV.y * 19.0 - water_clock * 16.0 + angle * 3.0) + 0.022 * sin(UV.y * 31.0 - water_clock * 23.0 - angle * 2.0));
	VERTEX = center + radial * ring_data[ring].w * ripple;
	NORMAL = radial;
	if (UV.x < -0.5) {
		VERTEX = center;
		NORMAL = tangent * (UV.y < 0.5 ? -1.0 : 1.0);
	}
	axial = UV.y;
	around = angle;
}

void fragment() {
	float rim = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 2.5);
	float streak = pow(max(cos(around + 0.6 + 0.17 * sin(axial * 8.0 - water_clock * 5.0)), 0.0), 18.0);
	float flow = 0.78 + 0.22 * sin(axial * 20.0 - water_clock * 19.0);
	float broad_glint = pow(max(dot(NORMAL, normalize(vec3(-0.38, 0.32, 0.87))), 0.0), 10.0);
	float roundness = 0.82 + 0.18 * max(dot(NORMAL, normalize(vec3(-0.45, 0.65, 0.60))), 0.0);
	ALBEDO = mix(water_tint.rgb * roundness, vec3(0.49, 0.92, 0.95), rim * 0.25);
	ALBEDO += vec3(0.34, 0.39, 0.37) * (streak * 0.45 + broad_glint * 0.65) * flow;
	ROUGHNESS = 0.22;
	SPECULAR = 0.65;
	EMISSION = water_tint.rgb * 0.10;
}
