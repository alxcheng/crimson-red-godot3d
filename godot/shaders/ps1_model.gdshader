shader_type spatial;
// PS1-style model shader: vertices snap to the low-res pixel grid (the wobble), lighting is
// computed per vertex (flat-shaded faces stay flat), no specular, no fancy materials.
// Texture mapping is not used yet: models are flat colour. When textures arrive, sample them
// with filter_nearest and add affine mapping here.
render_mode vertex_lighting, specular_disabled, cull_back;

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec2 snap_resolution = vec2(400.0, 225.0);   // keep equal to the internal render size
uniform float snap_amount : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec2 ndc = clip.xy / clip.w;
	vec2 grid = snap_resolution * 0.5;
	vec2 snapped = floor(ndc * grid + 0.5) / grid;
	clip.xy = mix(ndc, snapped, snap_amount) * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 1.0;
}
