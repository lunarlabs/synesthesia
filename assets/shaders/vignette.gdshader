shader_type canvas_item;

uniform float strength : hint_range(0.0, 2.0) = 1.2;
uniform float radius : hint_range(0.0, 1.0) = 0.6;

void fragment() {
	vec2 uv = UV - 0.5;
	float dist = length(uv);
	float vignette = smoothstep(radius, radius - 0.3, dist);
	COLOR = vec4(0., 0., 0., (1.0 - vignette) * strength);
}

//void light() {
//	// Called for every pixel for every light affecting the CanvasItem.
//	// Uncomment to replace the default light processing function with this one.
//}
