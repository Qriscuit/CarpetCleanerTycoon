shader_type canvas_item;
render_mode unshaded, blend_disabled;

// GLES3/Compatibility supplies the screen mipmaps only while this is visible.
// One filtered sample keeps this short transition light on mobile hardware.
uniform sampler2D room_screen : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float blur_amount : hint_range(0.0, 1.0) = 0.0;
uniform float max_radius_pixels : hint_range(0.0, 12.0) = 4.0;

void fragment() {
	float radius = max_radius_pixels * blur_amount;
	float lod = log2(1.0 + radius);
	COLOR = vec4(textureLod(room_screen, SCREEN_UV, lod).rgb, 1.0);
}
