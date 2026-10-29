shader_type canvas_item;
// Pixel-art pass for the whole 3D scene: everything is patterned. The screen is sampled on a 640x360 logical grid
// (exactly 2x the 1280x720 base, 3x at 1080p, 4x at 1440p: an integer ratio, so the pattern never shimmers),
// then shaded like a cel shader whose band edges are dithered:
//   1. luminance is split into a few BANDS (perceptual curve, so shadows keep detail);
//   2. the edge between two bands is a 2x2 ordered (Bayer) pattern: 25% / 50% / 75% mixes of the two band tones;
//      the Flowerwall CRT's horizontal blur and phosphor mask then melt that pattern into the in-between shade
//      (the Sonic 2 waterfall trick);
//   3. the chroma is quantised to a coarse level count with the same pattern, so colours dither too.
// The pattern lives on the screen grid (not on the objects), like the old consoles.
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform vec2 grid = vec2(960.0, 540.0);
uniform float bands : hint_range(2.0, 12.0) = 5.0;
uniform float colour_levels : hint_range(3.0, 32.0) = 9.0;
uniform float pattern : hint_range(0.0, 1.5) = 1.0;
uniform float saturation : hint_range(0.5, 1.6) = 1.12;
uniform float contrast : hint_range(0.8, 1.5) = 1.08;
// Limited-palette mode (an experiment, easy to roll back: set use_palette to false, or press P in the sandbox):
// every pixel snaps to the nearest of the fixed colours in ui/palette.gd; between the two nearest it picks by the 2x2 Bayer pattern.
uniform bool use_palette = false;
uniform sampler3D lut_a : filter_nearest, repeat_disable;   // nearest palette colour + mix amount (ui/palette.gd)
uniform sampler3D lut_b : filter_nearest, repeat_disable;   // second nearest palette colour
const float LUT_N = 32.0;

const float BAYER2[4] = float[4](0.0, 2.0, 3.0, 1.0);

void fragment() {
	vec2 cell = floor(SCREEN_UV * grid);
	vec3 c = textureLod(screen_tex, (cell + 0.5) / grid, 0.0).rgb;
	float luma = max(dot(c, vec3(0.299, 0.587, 0.114)), 0.0001);
	c = mix(vec3(luma), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	ivec2 p = ivec2(mod(cell, 2.0));
	if (use_palette) {
		vec3 uvw = (floor(clamp(c, 0.0, 1.0) * (LUT_N - 1.0) + 0.5) + 0.5) / LUT_N;
		vec4 la = textureLod(lut_a, uvw, 0.0);
		vec3 c1 = la.rgb;
		vec3 c2 = textureLod(lut_b, uvw, 0.0).rgb;
		float mixv = la.a;                                                   // 0 = on the nearest colour, 0.5 = halfway
		float th = ((BAYER2[p.y * 2 + p.x] + 0.5) / 4.0) * 0.5 * pattern;   // 0.06 .. 0.44
		COLOR = vec4(mixv > th ? c2 : c1, 1.0);
	} else {
	float t = (BAYER2[p.y * 2 + p.x] + 0.5) / 4.0 - 0.5;            // -0.375 .. +0.375: one of four thresholds
	// luminance bands (perceptual: sqrt), with the dithered edge
	float l = sqrt(clamp(dot(c, vec3(0.299, 0.587, 0.114)), 0.0, 1.0));
	float lb = floor(l * bands + t * pattern + 0.5) / bands;
	float scale = (lb * lb) / max(l * l, 0.0001);
	c = clamp(c * scale, 0.0, 1.0);
	// coarse colour levels, dithered with the same pattern
	c = floor(c * colour_levels + t * pattern * 0.6 + 0.5) / colour_levels;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
	}
}
