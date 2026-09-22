shader_type spatial;
render_mode unshaded;

uniform vec4 water_tint : source_color = vec4(0.20, 0.76, 0.83, 1.0);

void fragment() {
	float rim = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 3.0);
	ALBEDO = mix(water_tint.rgb, vec3(0.65, 0.91, 0.97), rim * 0.48);
	ROUGHNESS = 0.20;
	SPECULAR = 0.80;
	EMISSION = water_tint.rgb * 0.10;
}
