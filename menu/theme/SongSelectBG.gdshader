shader_type canvas_item;

// --- Uniforms ---
// Speed of the camera movement
uniform float speed : hint_range(0.1, 5.0) = 1.0;

// Spacing between each torus in the tunnel
uniform float spacing : hint_range(2.0, 10.0) = 4.0;

// Torus dimensions: x = major radius (ring size), y = minor radius (thickness)
uniform vec2 torus_size = vec2(1.5, 0.2);

// Color of the torus
uniform vec3 object_color : source_color = vec3(0.1, 0.6, 0.9);

// Background/Fog color
uniform vec3 fog_color : source_color = vec3(0.05, 0.05, 0.1);

// Maximum number of raymarching steps (higher = better quality but slower)
const int MAX_STEPS = 100;

// Maximum distance to march before giving up (far clip plane)
const float MAX_DIST = 50.0;

// Surface hit threshold (how close we need to get to consider it a hit)
const float SURF_DIST = 0.001;

// --- Signed Distance Functions (SDF) ---

// Torus SDF (Oriented in XY plane for Z-axis flythrough)
// p: current point in 3D space
// t: dimensions (x = radius, y = thickness)
float sdTorus(vec3 p, vec2 t) {
    vec2 q = vec2(length(p.xy) - t.x, p.z);
    return length(q) - t.y;
}

// Scene Map Function
// Calculates the closest distance to any object in the scene
float map(vec3 p) {
    // 1. Infinite Repetition (Domain Warping)
    // We wrap the Z coordinate using mod to create infinite copies.
    // The '- 0.5 * spacing' centers the domain so the torus sits in the middle of the cell.
    float z = mod(p.z, spacing) - 0.5 * spacing;

    // Create a new position vector with the wrapped Z
    vec3 p_rep = vec3(p.x, p.y, z);

    // 2. Optional: Rotation (Spinning effect)
    // Rotate around Z axis based on absolute Z position to make the tunnel twist
    float angle = p.z * 0.1;
    float s = sin(angle);
    float c = cos(angle);
    mat2 rot = mat2(vec2(c, -s), vec2(s, c));
    p_rep.xy = p_rep.xy * rot;

    // 3. Return distance to the torus
    return sdTorus(p_rep, torus_size);
}

// --- Raymarcher ---

// Casts a ray from 'ro' (Ray Origin) in direction 'rd' (Ray Direction)
float ray_march(vec3 ro, vec3 rd) {
    float dO = 0.0; // Distance Origin (total distance traveled)

    for(int i = 0; i < MAX_STEPS; i++) {
        vec3 p = ro + rd * dO; // Current position along the ray
        float dS = map(p);     // Distance to closest Surface

        dO += dS; // March forward

        // Break if we hit something or went too far
        if(dO > MAX_DIST || abs(dS) < SURF_DIST) {
            break;
        }
    }

    return dO;
}

// Calculates the normal vector at a surface point
// Used for lighting calculations
vec3 get_normal(vec3 p) {
    float d = map(p);
    vec2 e = vec2(0.01, 0.0);

    vec3 n = d - vec3(
        map(p - e.xyy),
        map(p - e.yxy),
        map(p - e.yyx)
    );

    return normalize(n);
}

// Calculates simple lighting based on normal
float get_light(vec3 p) {
    // Light position (relative to camera or fixed in world)
    // Here we place a light slightly ahead of the point to illuminate the tunnel
    vec3 light_pos = vec3(0.0, 0.0, p.z - 2.0);

    vec3 l = normalize(light_pos - p);
    vec3 n = get_normal(p);

    // Dot product gives diffuse intensity (0 to 1)
    float dif = clamp(dot(n, l), 0.0, 1.0);
    return dif;
}

void fragment() {
    // 1. Aspect Ratio Correction
    // SCREEN_PIXEL_SIZE is vec2(1.0/width, 1.0/height)
    // We center UVs to -0.5 to 0.5 first
    vec2 uv = UV - 0.5;

    // Fix aspect ratio so X is wider than Y on landscape screens
    uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;

    // 2. Camera Setup
    // Ray Origin (Camera Position)
    // Move camera along Z axis based on time
    vec3 ro = vec3(0.0, 0.0, TIME * speed);

    // Ray Direction
    // The UV becomes the XY direction, Z is forward (1.0)
    vec3 rd = normalize(vec3(uv, 1.0));

    // 3. Perform Raymarching
    float d = ray_march(ro, rd);

    // 4. Coloring
    vec3 col = vec3(0.0);

    if(d < MAX_DIST) {
        // We hit something
        vec3 p = ro + rd * d;
        float dif = get_light(p);

        // Base color * light intensity
        col = object_color * dif;

        // Add simple Fresnel rim lighting for a "glowing" edge look
        // (optional, makes it look sci-fi)
        // float fresnel = pow(1.0 + dot(rd, get_normal(p)), 2.0);
        // col += vec3(0.5, 0.8, 1.0) * fresnel;
    }

    // 5. Fog / Fade to background
    // Mix the object color with the fog color based on distance
    // This hides the artifacts where the raymarcher hits MAX_DIST
    col = mix(col, fog_color, 1.0 - exp(-d * 0.08));

    // Output final color
    COLOR = vec4(col, 1.0);
}