shader_type spatial;
render_mode blend_mix, depth_draw_opaque, depth_test_default, cull_back, diffuse_lambert, specular_schlick_ggx;

// Index 0 - This now perfectly matches the index of Shader 1
instance uniform vec4 measure_tint : source_color = vec4(1.0);

global uniform float beat : hint_range(0.0, 1.0);
uniform sampler2D curve_frg_6 : repeat_disable;

void fragment() {
    // 1. Base Material
    ALBEDO = vec3(0.064697);
    
    // 2. Emission Logic
    // Condensing the node math: UV.y minus beat, then fract, then texture lookup
    float scroll_val = fract(UV.y - beat);
    float curve_val = texture(curve_frg_6, vec2(scroll_val, 0.0)).r;
    
    // Mixing black with the tint color based on the curve is mathematically 
    // identical to just multiplying them, which is much cheaper.
    EMISSION = measure_tint.rgb * curve_val;
}