shader_type spatial;
render_mode blend_mix, depth_draw_opaque, depth_test_default, cull_back, diffuse_lambert, specular_schlick_ggx;

instance uniform float z_limit;
uniform sampler2D pattern : source_color;

varying vec3 world_pos;

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float val = world_pos.z;

    float afwidth = fwidth(val);

    ALBEDO = texture(pattern, UV).rgb;
    ROUGHNESS = 0.4;
    float mask = smoothstep(z_limit - afwidth, z_limit + afwidth, val);
    ALPHA = 1. - mask;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}
