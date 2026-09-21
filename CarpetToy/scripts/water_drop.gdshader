shader_type spatial;
render_mode diffuse_burley, world_vertex_coords;

// INSTANCE_CUSTOM = (birth modulo 8 seconds, flight seconds, launch delta X,
// launch delta Z). The MultiMesh transform supplies radius and landing position.
// The controller clears duration on landing, so modulo time cannot revive drops.
uniform float water_clock = 0.0;
uniform float launch_height : hint_range(0.01, 2.0) = 0.30;
uniform vec4 drop_tint : source_color = vec4(0.23, 0.71, 0.86, 1.0);

void vertex() {
	float duration = INSTANCE_CUSTOM.g;
	float age = mod(water_clock - INSTANCE_CUSTOM.r + 8.0, 8.0);
	vec3 landing = MODEL_MATRIX[3].xyz;
	if (duration <= 0.0 || age >= duration) {
		// Degenerate geometry below the floor avoids alpha, discard, and an
		// additional transparent draw. The fixed pool can stay on the GPU.
		VERTEX = landing - vec3(0.0, 10.0, 0.0);
	} else {
		float t = clamp(age / duration, 0.0, 1.0);
		float impact = smoothstep(0.87, 1.0, t);
		vec3 stretch = vec3(1.0 + impact * 0.34, mix(1.16, 0.55, impact), 1.0 + impact * 0.34);
		vec3 shape = (VERTEX - landing) * stretch;
		vec3 flight = vec3(INSTANCE_CUSTOM.b * (1.0 - t), launch_height * (1.0 - t * t), INSTANCE_CUSTOM.a * (1.0 - t));
		VERTEX = landing + shape + flight;
		NORMAL = normalize(NORMAL / stretch);
	}
}

void fragment() {
	float edge = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 3.0);
	float glint = pow(max(dot(NORMAL, normalize(vec3(-0.42, 0.64, 0.65))), 0.0), 16.0);
	ALBEDO = mix(drop_tint.rgb, vec3(0.57, 0.86, 0.94), edge * 0.45);
	ALBEDO += vec3(0.68, 0.86, 0.91) * glint * 0.85;
	ROUGHNESS = 0.14;
	SPECULAR = 0.85;
	EMISSION = vec3(0.48, 0.78, 0.88) * glint * 0.24;
}
