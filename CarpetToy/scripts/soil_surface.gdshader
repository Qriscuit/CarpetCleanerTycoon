shader_type spatial;
render_mode diffuse_burley, cull_disabled;

uniform sampler2D clean_map : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 clean_color : source_color = vec4(1.0);
uniform vec4 surface_tint : source_color = vec4(1.0);
uniform sampler2D soil_map : source_color, filter_linear_mipmap;
uniform sampler2D coverage : filter_linear, repeat_disable, hint_default_white;
uniform sampler2D wetness : filter_linear, repeat_disable, hint_default_black;
uniform bool wet_recipe = false;
// A small persistent density atlas supplies connected puddles. Five samples per
// fragment are independent of the number of hose drops; no transparent pass.
uniform bool blob_enabled = false;
uniform sampler2D blob_density : filter_linear, repeat_disable, hint_default_black;
uniform vec2 blob_texel_size = vec2(0.0052083333, 0.003125);
uniform float blob_threshold : hint_range(0.05, 0.6) = 0.20;
uniform float blob_edge_softness : hint_range(0.01, 0.12) = 0.045;
uniform vec4 blob_tint : source_color = vec4(0.30, 0.75, 0.89, 1.0);
uniform float blob_tint_strength : hint_range(0.0, 1.0) = 0.30;
uniform float blob_edge_motion : hint_range(0.0, 1.0) = 0.70;
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
	float water = wet_recipe ? texture(wetness, rug_uv).r : 0.0;
	vec3 clean = texture(clean_map, UV).rgb * clean_color.rgb * surface_tint.rgb;
	vec3 pale_dust = mix(texture(soil_map, rug_uv).rgb, dust_tint.rgb, 0.70);
	vec3 dry_color = mix(clean, pale_dust, soil * dust_strength);
	vec3 wet_color = mix(dry_color * vec3(0.72, 0.80, 0.84), vec3(0.33, 0.62, 0.70), 0.10);
	ALBEDO = mix(dry_color, wet_color, water * 0.72);
	ROUGHNESS = mix(0.96, 0.48, water);
	SPECULAR = mix(0.12, 0.38, water);
	if (blob_enabled) {
		// Sub-texel displacement moves only the water boundary. The underlying
		// carpet pattern remains still and visible through the opaque shading.
		vec2 ripple = vec2(
			sin(rug_uv.y * 47.0 + rug_uv.x * 19.0 + TIME * 1.10),
			sin(rug_uv.x * 43.0 - rug_uv.y * 17.0 - TIME * 0.85)
		);
		vec2 blob_uv = rug_uv + ripple * blob_texel_size * blob_edge_motion;
		float density = texture(blob_density, blob_uv).r;
		float left_density = texture(blob_density, blob_uv - vec2(blob_texel_size.x, 0.0)).r;
		float right_density = texture(blob_density, blob_uv + vec2(blob_texel_size.x, 0.0)).r;
		float top_density = texture(blob_density, blob_uv - vec2(0.0, blob_texel_size.y)).r;
		float bottom_density = texture(blob_density, blob_uv + vec2(0.0, blob_texel_size.y)).r;
		float puddle = smoothstep(blob_threshold - blob_edge_softness, blob_threshold + blob_edge_softness, density);
		vec2 slope = vec2(right_density - left_density, bottom_density - top_density);
		// Atlas pixels represent almost equal distances in world X and Z.
		vec2 outward = -slope / max(length(slope), 0.0001);
		// Gradient-normalized distance keeps the curved rim a few atlas pixels
		// wide even after many drops saturate the interior density.
		float edge_distance = max(density - blob_threshold, 0.0) / max(length(slope), 0.025);
		float meniscus = puddle * (1.0 - smoothstep(0.25, 1.65, edge_distance));
		float facing_light = max(dot(outward, vec2(-0.60, -0.80)), 0.0);
		float crescent = pow(facing_light, 3.0) * meniscus;
		float reflected_light = crescent * (0.84 + ripple.x * 0.10);
		float opposite_rim = pow(max(dot(outward, vec2(0.60, 0.80)), 0.0), 3.0) * meniscus;
		float sky_sheen = pow(max(sin(rug_uv.x * 13.0 + rug_uv.y * 8.0 + TIME * 0.28), 0.0), 6.0);
		sky_sheen *= smoothstep(blob_threshold, blob_threshold + 0.38, density);
		vec3 submerged = mix(ALBEDO * vec3(0.83, 0.97, 1.03), blob_tint.rgb, blob_tint_strength);
		submerged *= 1.0 - opposite_rim * 0.11;
		submerged += vec3(0.57, 0.82, 0.88) * reflected_light * 0.70;
		submerged += vec3(0.28, 0.53, 0.64) * sky_sheen * 0.15;
		ALBEDO = mix(ALBEDO, submerged, puddle);
		ROUGHNESS = mix(ROUGHNESS, 0.16, puddle);
		SPECULAR = mix(SPECULAR, 0.82, puddle);
		// Rounded edge normals catch the scene light; restrained emission keeps
		// the reflected sky readable in the game's deliberately soft lighting.
		vec3 world_slope = vec3(outward.x, 0.0, outward.y) * 0.42;
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(world_slope, 0.0)).xyz * meniscus);
		EMISSION = (vec3(0.45, 0.76, 0.87) * reflected_light * 0.23 + vec3(0.23, 0.48, 0.59) * sky_sheen * 0.08) * puddle;
	}
}
