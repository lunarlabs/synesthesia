shader_type canvas_item;

uniform int line_count;
uniform float line_offsets[32];
uniform float line_heights[32];

uniform vec4 top_color : source_color = vec4(1.0);
uniform vec4 bottom_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
    vec4 base = texture(TEXTURE, UV);

    // If pixel is fully transparent, just output transparent
    if (base.a <= 0.0) {
        COLOR = vec4(0.0);
    } else {
        float y = UV.y;
        int line = -1;

        // Find which line this pixel belongs to
        for (int i = 0; i < line_count; i++) {
            float top = line_offsets[i];
            float bottom = top + line_heights[i];

            if (y >= top && y < bottom) {
                line = i;
                break;
            }
        }

        if (line == -1) {
            // Outside text bounds → just render normally
            COLOR = base;
        } else {
            float top = line_offsets[line];
            float bottom = top + line_heights[line];
            float t = clamp((y - top) / (bottom - top), 0.0, 1.0);

            vec4 grad = mix(top_color, bottom_color, t);
            COLOR = vec4(grad.rgb, grad.a * base.a);
        }
    }
}
