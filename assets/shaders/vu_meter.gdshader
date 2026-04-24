shader_type spatial;
render_mode blend_mix, depth_draw_opaque, depth_test_default, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform vec3 off_color : source_color = vec3(0.0);
uniform vec3 on_color : source_color = vec3(1.0);
global uniform sampler2D viz : source_color, hint_default_black, filter_nearest;

void fragment(){
    float val = texture(viz, UV).r;
    float tex_v = 1. - UV.y;
    float afwidth = fwidth(tex_v);

    ALBEDO = vec3(0.05);
    float mask = smoothstep(val - afwidth, val + afwidth, tex_v);
    EMISSION = mix(on_color, off_color, mask);
}
