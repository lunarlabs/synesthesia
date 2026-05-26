shader_type spatial;
render_mode blend_mix, depth_draw_opaque, depth_test_default, cull_back, diffuse_lambert, specular_schlick_ggx;

// Instance uniforms MUST be in the exact same order across materials on the same mesh.
instance uniform vec4 measure_tint : source_color = vec4(1.0); // Index 0
instance uniform int this_track = 0;                           // Index 1
instance uniform bool phrase = false;                          // Index 2

global uniform int current_track;

uniform sampler2D tex_frg_23 : source_color;
uniform sampler2D tex_frg_38;
uniform sampler2D tex_frg_33 : source_color;
uniform sampler2D tex_frg_45;

void fragment() {
    // 1. Base Material Properties
    ALBEDO = texture(tex_frg_23, UV).rgb;
    ROUGHNESS = 0.1;
    
    // 2. Normal Map
    NORMAL_MAP = texture(tex_frg_45, UV).rgb;
    NORMAL_MAP_DEPTH = 0.15;

    // 3. Emission Logic
    vec3 final_emission = vec3(0.0);
    
    // Only calculate the complex emission if this track is the current track
    if (current_track == this_track) {
        vec3 tex38_color = texture(tex_frg_38, UV).rgb;
        
        // The visual shader logic was mixing black and 0.15 based on the 'phrase' boolean
        vec3 phrase_multiplier = phrase ? vec3(0.15) : vec3(0.0);
        vec3 base_emission = (measure_tint.rgb * tex38_color) * phrase_multiplier;
        
        vec3 tex33_color = texture(tex_frg_33, UV).rgb;
        final_emission = mix(base_emission, vec3(0.4), tex33_color);
    }
    
    EMISSION = final_emission;
}