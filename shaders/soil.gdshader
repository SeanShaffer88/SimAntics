shader_type canvas_item;
// Draws the painted soil (2x2 art pixels) with smooth, anti-aliased tunnel walls and
// fine sand grain at full screen resolution. The open-air mask is blurred slightly and
// the wall drawn where it crosses one half, so walls follow smooth curves instead of
// stepping along the art grid. Near a wall, colour is read from the correct side so
// the edge stays crisp, and the packed lining is redrawn along the smooth wall.

uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform vec2 art_size = vec2(640.0, 296.0);
uniform float grain_strength = 0.09;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float mask_at(vec2 uv, vec2 texel) {
	// 3x3 tent blur: rounds off the steps of the art grid
	float m = texture(mask_tex, uv).r * 4.0;
	m += (texture(mask_tex, uv + vec2(texel.x, 0.0)).r + texture(mask_tex, uv - vec2(texel.x, 0.0)).r
		+ texture(mask_tex, uv + vec2(0.0, texel.y)).r + texture(mask_tex, uv - vec2(0.0, texel.y)).r) * 2.0;
	m += texture(mask_tex, uv + texel).r + texture(mask_tex, uv - texel).r
		+ texture(mask_tex, uv + vec2(texel.x, -texel.y)).r + texture(mask_tex, uv + vec2(-texel.x, texel.y)).r;
	return m / 16.0;
}

void fragment() {
	vec2 texel = 1.0 / art_size;
	float m = mask_at(UV, texel);
	float mx = mask_at(UV + vec2(texel.x, 0.0), texel) - mask_at(UV - vec2(texel.x, 0.0), texel);
	float my = mask_at(UV + vec2(0.0, texel.y), texel) - mask_at(UV - vec2(0.0, texel.y), texel);
	vec2 g = vec2(mx, my);
	vec2 n = length(g) > 0.001 ? normalize(g) : vec2(0.0);  // points into the open space
	vec3 air_c = texture(TEXTURE, UV + n * texel * 1.5).rgb;
	vec3 soil_c = texture(TEXTURE, UV - n * texel * 1.5).rgb;
	float w = fwidth(m) * 0.9 + 0.0001;
	float a = smoothstep(0.5 - w, 0.5 + w, m);
	// sand grain: fine specks in the soil, at about half a screen pixel
	vec2 cell = floor(UV * art_size * 4.0);
	float grain = hash(cell) - 0.5;
	float speck = step(0.985, hash(cell + 17.0));
	soil_c *= 1.0 + grain * grain_strength;
	soil_c = mix(soil_c, soil_c * 1.35 + 0.04, speck * 0.6);
	// packed, smoothed soil lining the wall, brighter where it is a trodden floor
	float lining = smoothstep(0.18, 0.46, m) * (1.0 - a);
	float floor_side = clamp(-n.y, 0.0, 1.0);
	soil_c = mix(soil_c, soil_c * (1.12 + 0.12 * floor_side) + 0.015, lining);
	COLOR = vec4(mix(soil_c, air_c, a), 1.0);
}
