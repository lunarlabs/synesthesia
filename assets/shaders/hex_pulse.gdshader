// hex_pulse.gdshader
shader_type canvas_item;

uniform float speed : hint_range(0.0, 3.0) = 0.8;
uniform float line_width : hint_range(0.001, 0.05) = 0.018;
uniform vec4 line_color : source_color = vec4(0.1, 0.49, 0.91, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.07;
uniform float pulse_strength : hint_range(0.0, 1.0) = 0.05;

// Axial hex grid distance function (returns distance to edge)
float hex_dist(vec2 p) {
    p = abs(p);
    // 1.7320508 is sqrt(3)
    return max(dot(p, normalize(vec2(1.0, 1.7320508))), p.x);
}

// Calculates both the local coordinates within the hex, and the hex's center ID
vec4 hex_coords(vec2 uv) {
    // Grid bounding box for pointy-topped hexagons
    vec2 r = vec2(1.0, 1.7320508);
    vec2 h = r * 0.5;

    // Create two overlapping offset grids
    vec2 a = mod(uv, r) - h;
    vec2 b = mod(uv - h, r) - h;

    // Determine which grid center the current pixel is closest to
    vec2 gv = dot(a, a) < dot(b, b) ? a : b;

    // The center ID is the original UV minus the local offset
    vec2 id = uv - gv;

    // Return local coords (xy) and center ID (zw)
    return vec4(gv.x, gv.y, id.x, id.y);
}

void fragment() {
    // Tile density. Note: For perfect hexes, the aspect ratio of your sprite/screen
    // should ideally match the ratio of these numbers (18:10 or 1.8).
    vec2 uv = UV * vec2(16.0, 9.0); 

    vec4 hex = hex_coords(uv);
    vec2 local = vec2(hex.x, hex.y);
    vec2 center = vec2(hex.z, hex.w);

    float d = hex_dist(local);

    // Your original logic draws solid pulsing hexes separated by transparent gaps
    float edge = 1.0 - smoothstep(0.5 - line_width, 0.5, d);

    float pulse = sin(TIME * speed + center.x * 0.4 + center.y * 0.7) * 0.5 + 0.5;
    float alpha = edge * (base_alpha + pulse * pulse_strength);

    COLOR = vec4(line_color.rgb, alpha);
}