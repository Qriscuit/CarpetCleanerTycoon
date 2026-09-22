shader_type spatial;
render_mode diffuse_burley, world_vertex_coords;

// INSTANCE_CUSTOM = (birth modulo 8 seconds, flight seconds, launch delta X,
// launch delta Z). A single sphere is deformed into a connected three-lobed
// membrane: the phone gets the requested "three balls under cloth" silhouette
// without three bodies, cloth simulation, or one draw call per drop.
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
		vec3 shape = VERTEX - landing;
		vec2 planar = shape.xz;
		vec2 planar_direction = planar / max(length(planar), 0.0001);
		float rolling_phase = t * 4.8 + INSTANCE_CUSTOM.r * 0.71;
		// Three broad directional bulges orbit around one watertight shell. Their
		// overlap keeps the center joined instead of looking like separate balls.
		for (int lobe_index = 0; lobe_index < 3; lobe_index++) {
			float angle = rolling_phase + float(lobe_index) * 6.28318530718 / 3.0;
			vec2 lobe_direction = vec2(cos(angle), sin(angle));
			float facing = pow(max(dot(planar_direction, lobe_direction), 0.0), 3.0);
			float middle = 1.0 - smoothstep(0.45, 1.05, abs(shape.y) / max(length(shape), 0.0001));
			shape.xz += lobe_direction * length(shape) * facing * middle * 0.31;
		}
		shape.y += sin(rolling_phase * 1.7 + atan(planar.y, planar.x) * 2.0) * length(shape) * 0.055;
		vec3 stretch = vec3(1.0 + impact * 0.42, mix(1.14, 0.46, impact), 1.0 + impact * 0.42);
		shape *= stretch;
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
