shader_type canvas_item;
render_mode unshaded, blend_add;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float kernel = max(1.0 - dot(p, p), 0.0);
	// Alpha stays one: additive blending must not square the soft kernel.
	COLOR = vec4(vec3(kernel * kernel * COLOR.r), 1.0);
}
