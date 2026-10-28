shader_type canvas_item;
// PS1-style post pass, run on the low-res viewport image: reduce each colour channel to a few
// levels and hide the banding with a 4x4 ordered (Bayer) dither. The dither pattern is laid on
// the LOW-res pixel grid, so its dots are as big as the game's pixels.

uniform vec2 internal_size = vec2(400.0, 225.0);   // keep equal to the SubViewport size
uniform float levels : hint_range(2.0, 64.0) = 16.0;   // PS1 was 32 (5 bits); lower = grainier
uniform float dither_strength : hint_range(0.0, 2.0) = 1.0;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

void fragment() {
	vec2 px = floor(UV * internal_size);
	vec3 c = texture(TEXTURE, (px + 0.5) / internal_size).rgb;
	int i = int(mod(px.x, 4.0)) + int(mod(px.y, 4.0)) * 4;
	float t = (BAYER[i] + 0.5) / 16.0 - 0.5;
	c = floor(c * (levels - 1.0) + 0.5 + t * dither_strength) / (levels - 1.0);
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
