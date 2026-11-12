shader_type canvas_item;

// --- Uniforms ---

global uniform sampler2D viz;
uniform vec3 camera_location = vec3(3.0, 0.28, -10.0);

// Maximum number of raymarching steps
const int MAX_STEPS = 75;
 
// Maximum distance to march before giving up
const float MAX_DIST = 50.0;

// Surface hit threshold
const float SURF_DIST = 0.001;

// Constants for domain repetition
const float SECTOR_SIZE = TAU / 64.0;
const float INV_SECTOR = 64.0 / TAU;

// --- 2D Planar Rotation Helper ---
vec2 rot2D(vec2 v, float a) {
    float s = sin(a);
    float c = cos(a);
    return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

// --- Signed Distance Functions (SDF) ---

float sdOctahedron(vec3 p, float s) {
    p = abs(p);
    float m = p.x + p.y + p.z - s;
    vec3 q;
    if (3.0 * p.x < m) q = p.xyz;
    else if (3.0 * p.y < m) q = p.yzx;
    else if (3.0 * p.z < m) q = p.zxy;
    else return m * 0.57735027;
    
    float k = clamp(0.5 * (q.z - q.y + s), 0.0, s); 
    return length(vec3(q.x, q.y - s + k, q.z - k)); 
}

float sdParallelogram(in vec2 p, float wi, float he, float sk) {
    vec2 e = vec2(sk, he);
    p = (p.y < 0.0) ? -p : p;
    vec2 w = p - e; 
    w.x -= clamp(w.x, -wi, wi);
    vec2 d = vec2(dot(w, w), -w.y);
    float s = p.x * e.y - p.y * e.x;
    p = (s < 0.0) ? -p : p;
    vec2 v = p - vec2(wi, 0.0); 
    v -= e * clamp(dot(v, e) / dot(e, e), -1.0, 1.0);
    d = min(d, vec2(dot(v, v), wi * he - abs(s)));
    return sqrt(d.x) * sign(-d.y);
}

float sdVerticalCapsule(vec3 p, float h, float r) {
    p.y -= clamp(p.y, 0.0, h);
    return length(p) - r;
}

float sdTorus(vec3 p, vec2 t) {
    vec2 q = vec2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

// --- Ring Helper Function ---
float opRing(vec3 p, float r, float a, float y_offset, float rot_dir, bool is_top) {
    float cur_a = a - rot_dir * (TIME * 0.25);
    
    // Wedge calculation using reciprocal multiplication
    float id = floor(cur_a * INV_SECTOR + 0.5);
    float local_a = cur_a - id * SECTOR_SIZE;
    
    // Fast periodic index wrap for texture fetch
    int j = int(mod(mod(id, 64.0) + 64.0, 16.0));
    float h = texelFetch(viz, ivec2(j, 0), 0).x;
    float h4 = h * 3.0;
    
    // Reconstruct query offset directly
    vec2 d_xz = vec2(sin(local_a) * r, cos(local_a) * r - 11.0);
    float y_pos = is_top ? y_offset : y_offset - h4;
    vec3 q = vec3(d_xz.x, p.y - y_pos, d_xz.y);
    
    return sdVerticalCapsule(q, h4, 0.1);
}

// --- Fast Distance Map (Inner Marching & Normals) ---
float map_dist(vec3 p) {
    float r_xz = length(p.xz);
    
    // 1. Central Outer Walls
    float d = sdParallelogram(vec2(r_xz - 10.0, p.y - 5.0), 0.5, 1.0, -0.8);
    d = min(d, sdParallelogram(vec2(r_xz - 10.0, p.y + 5.0), 0.5, 1.0, 0.8));
    
    // 2. Octahedron (2D axis rotations avoid building 3x3 matrices)
    vec3 q_oct = p;
    q_oct.xz = rot2D(q_oct.xz, TIME * 0.3);
    q_oct.yz = rot2D(q_oct.yz, TIME * 0.2);
    d = min(d, sdOctahedron(q_oct, 3.0));
    
    // 3. Torus R=11 (Shares r_xz)
    d = min(d, length(vec2(r_xz - 11.0, p.y)) - 0.1);
    
    // 4. Rotating Torus 1 (Precalculated PI/3 rotation)
    vec3 q_t1 = p;
    q_t1.xz = vec2(q_t1.x * 0.5 - q_t1.z * 0.8660254, q_t1.x * 0.8660254 + q_t1.z * 0.5);
    q_t1.yz = rot2D(q_t1.yz, TIME * 0.65);
    d = min(d, sdTorus(q_t1, vec2(12.5, 0.3)));
    
    // 5. Rotating Torus 2 (Exact PI/2 rotation: (y, z) -> (-z, y))
    vec3 q_t2 = p;
    q_t2.xz = rot2D(q_t2.xz, TIME * -0.45);
    q_t2.yz = vec2(-q_t2.z, q_t2.y);
    d = min(d, sdTorus(q_t2, vec2(13.0, 0.3)));
    
    // 6. Visualizer Rings (Conservative bounding rejection)
    float d_bound_top = length(vec2(abs(r_xz - 11.0), max(0.0, max(0.4 - p.y, p.y - 4.6)))) - 0.15;
    float d_bound_bot = length(vec2(abs(r_xz - 11.0), max(0.0, max(-4.6 - p.y, p.y + 0.4)))) - 0.15;
    
    // Only execute atan() and texelFetch() when the ray is close to the rings
    if (d_bound_top < d || d_bound_bot < d) {
        float a = atan(p.x, p.z);
        if (d_bound_top < d) {
            d = min(d, opRing(p, r_xz, a, 0.5, 1.0, true));
        }
        if (d_bound_bot < d) {
            d = min(d, opRing(p, r_xz, a, -0.5, -1.0, false));
        }
    }
    
    return d;
}

// --- Material Query Map (Evaluated ONCE upon hit) ---
int get_object_id(vec3 p) {
    float r_xz = length(p.xz);
    float d = 1e10;
    int id = 0;
    
    float dist = sdParallelogram(vec2(r_xz - 10.0, p.y - 5.0), 0.5, 1.0, -0.8);
    if (dist < d) { d = dist; id = 1; }
    
    dist = sdParallelogram(vec2(r_xz - 10.0, p.y + 5.0), 0.5, 1.0, 0.8);
    if (dist < d) { d = dist; id = 2; }
    
    vec3 q_oct = p;
    q_oct.xz = rot2D(q_oct.xz, TIME * 0.3);
    q_oct.yz = rot2D(q_oct.yz, TIME * 0.2);
    dist = sdOctahedron(q_oct, 3.0);
    if (dist < d) { d = dist; id = 3; }
    
    float a = atan(p.x, p.z);
    dist = opRing(p, r_xz, a, 0.5, 1.0, true);
    if (dist < d) { d = dist; id = 4; }
    
    dist = opRing(p, r_xz, a, -0.5, -1.0, false);
    if (dist < d) { d = dist; id = 5; }
    
    dist = length(vec2(r_xz - 11.0, p.y)) - 0.1;
    if (dist < d) { d = dist; id = 6; }
    
    vec3 q_t1 = p;
    q_t1.xz = vec2(q_t1.x * 0.5 - q_t1.z * 0.8660254, q_t1.x * 0.8660254 + q_t1.z * 0.5);
    q_t1.yz = rot2D(q_t1.yz, TIME * 0.65);
    dist = sdTorus(q_t1, vec2(12.5, 0.3));
    if (dist < d) { d = dist; id = 7; }
    
    vec3 q_t2 = p;
    q_t2.xz = rot2D(q_t2.xz, TIME * -0.45);
    q_t2.yz = vec2(-q_t2.z, q_t2.y);
    dist = sdTorus(q_t2, vec2(13.0, 0.3));
    if (dist < d) { id = 8; }
    
    return id;
}

// --- Raymarcher ---
float ray_march(vec3 ro, vec3 rd) {
    float dO = 0.0;

    for (int i = 0; i < MAX_STEPS; i++) {
        vec3 p = ro + rd * dO;
        float dS = map_dist(p);
        dO += dS;

        if (dO > MAX_DIST || dS < SURF_DIST) {
            break;
        }
    }

    return dO;
}

// --- Surface Normal ---
vec3 get_normal(vec3 p) {
    float d = map_dist(p);
    vec2 e = vec2(0.01, 0.0);

    vec3 n = d - vec3(
        map_dist(p - e.xyy),
        map_dist(p - e.yxy),
        map_dist(p - e.yyx)
    );

    return normalize(n);
}

// --- Lighting (Reuses normal instead of recalculating it) ---
vec2 get_light(vec3 p, vec3 n, vec3 view_dir) {
    vec3 light_pos = vec3(0.5, -3.0, p.z - 4.0);
    vec3 l = normalize(light_pos - p);

    float dif = clamp(dot(n, l), 0.0, 1.0);
    vec3 h = normalize(l + view_dir);
    float base_spec = clamp(dot(n, h), 0.0, 1.0);
    
    return vec2(dif, base_spec);
}

// Branchless HSL to RGB conversion
vec3 hsl_to_rgb(float h, float s, float l) {
    vec3 rgb = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
    return l + s * (rgb - 0.5) * (1.0 - abs(2.0 * l - 1.0));
}

void fragment() {
    vec2 uv = UV - 0.5;
    uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;

    vec3 ro = camera_location + vec3(
        sin(TIME * 0.25) * 0.3,
        cos(TIME * 0.18) * 0.5,
        0.0
    );

    vec3 rd = normalize(vec3(uv, 1.0));

    float d = ray_march(ro, rd);

    vec3 bg_color = mix(vec3(0.02, 0.03, 0.08), vec3(0.08, 0.10, 0.22), 0.5 + 0.5 * uv.y);
    float haze = exp(-length(uv) * 2.5);
    bg_color += vec3(0.10, 0.18, 0.42) * haze * 0.55;
    
    vec3 col = bg_color;
    
    if (d < MAX_DIST) {
        vec3 p = ro + rd * d;
        int object_id = get_object_id(p);
        vec3 n = get_normal(p);
        vec2 lighting = get_light(p, n, -rd);
        
        float diffuse = lighting.x;
        float base_spec = lighting.y;
        float rim = pow(1.0 - max(dot(n, -rd), 0.0), 2.5);
        
        float hue = 0.55;
        float sat = 0.5;
        float lightness = 0.5;
        float shininess = 64.0;
        float spec_intensity = 0.8;
        vec3 specular_color = vec3(1.0);
        
        if (object_id == 1 || object_id == 2) {
            hue = mix(0.65, 0.60, (p.y + 5.0) * 0.1);
            sat = mix(0.45, 0.8, diffuse + rim * 0.35);
            lightness = mix(0.10, 0.35, diffuse + rim * 0.5);
            shininess = 32.0;
            spec_intensity = 0.85;
            specular_color = vec3(0.81, 0.918, 0.99); // Precomputed hsl_to_rgb(0.60, 0.9, 0.9)
        } else if (object_id == 3) {
            hue = mix(0.65, 0.70, (p.y + 3.0) * 0.1666667); 
            sat = mix(0.7, 1.0, diffuse + rim * 0.3);
            lightness = mix(0.20, 0.72, diffuse + rim * 0.8);
            shininess = 160.0;
            spec_intensity = 1.6;
            specular_color = vec3(0.995, 0.905, 0.959); // Precomputed hsl_to_rgb(0.90, 0.9, 0.95)
        } else if (object_id == 4 || object_id == 5) {
            float pulse = 0.65 + 0.35 * sin(TIME * 3.5 + p.x * 1.4 + p.y * 0.7);
            hue = mix(0.50, 0.58, (p.y + 5.0) * 0.1);
            sat = mix(0.6, 1.0, diffuse + rim * 0.4 + pulse * 0.2);
            lightness = mix(0.18, 0.62, diffuse + rim * 0.6 + pulse * 0.2);
            shininess = 90.0;
            spec_intensity = 1.2;
            specular_color = vec3(0.905, 0.973, 0.995); // Precomputed hsl_to_rgb(0.54, 0.9, 0.95)
        }
		else if (object_id == 6 || object_id == 7 || object_id == 8) {
			hue = mix(0.65, 0.60, (p.y + 5.0) * 0.1);
            sat = mix(0.0, 0.1, diffuse + rim * 0.35);
            lightness = mix(0.02, 0.1, diffuse + rim * 0.5);
            shininess = 16.0;
            spec_intensity = 0.25;
            specular_color = vec3(0.8, 0.8, 0.8);
		}
		
        
        float specular = pow(base_spec, shininess);
        vec3 surface_color = hsl_to_rgb(hue, sat, lightness);
        surface_color += specular_color * specular * spec_intensity;
        surface_color += specular_color * rim * (0.8 + diffuse);
        
        float fog_factor = smoothstep(0.0, MAX_DIST * 0.7, d);
        col = mix(surface_color, bg_color, fog_factor);
    }

    COLOR = vec4(col, 1.0);
}