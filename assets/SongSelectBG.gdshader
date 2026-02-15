shader_type canvas_item;

// --- Uniforms ---

global uniform sampler2D viz;

// Maximum number of raymarching steps (higher = better quality but slower)
const int MAX_STEPS = 100;

// Maximum distance to march before giving up (far clip plane)
const float MAX_DIST = 50.0;

// Surface hit threshold (how close we need to get to consider it a hit)
const float SURF_DIST = 0.001;

vec2 opRevolution(in vec3 p, float w){
	return vec2(length(p.xz) - w, p.y);
}

// --- Signed Distance Functions (SDF) ---

float sdOctahedron( vec3 p, float s )
{
  p = abs(p);
  float m = p.x+p.y+p.z-s;
  vec3 q;
       if( 3.0*p.x < m ) q = p.xyz;
  else if( 3.0*p.y < m ) q = p.yzx;
  else if( 3.0*p.z < m ) q = p.zxy;
  else return m*0.57735027;
    
  float k = clamp(0.5*(q.z-q.y+s),0.0,s); 
  return length(vec3(q.x,q.y-s+k,q.z-k)); 
}

float sdParallelogram( in vec2 p, float wi, float he, float sk ) {
    vec2 e = vec2(sk,he);
    p = (p.y<0.0)?-p:p;
    vec2  w = p - e; w.x -= clamp(w.x,-wi,wi);
    vec2  d = vec2(dot(w,w), -w.y);
    float s = p.x*e.y - p.y*e.x;
    p = (s<0.0)?-p:p;
    vec2  v = p - vec2(wi,0); v -= e*clamp(dot(v,e)/dot(e,e),-1.0,1.0);
    d = min( d, vec2(dot(v,v), wi*he-abs(s)));
    return sqrt(d.x)*sign(-d.y);
}

float sdVerticalCapsule( vec3 p, float h, float r )
{
  p.y -= clamp( p.y, 0.0, h );
  return length( p ) - r;
}

// --- Optimized Helper Function ---
// Calculates distance to a ring of capsules using domain repetition
float opRing(vec3 p, float y_offset, float rot_dir, bool is_top) {
    // 1. Convert to Polar Coordinates
    float r = length(p.xz);
    float a = atan(p.x, p.z); // Aligned with your sin(a)/cos(a) logic
    
    // 2. Apply Rotation
    a -= rot_dir * (TIME * 0.25);
    
    // 3. Domain Repetition (Fold Space)
    float sector_size = TAU / 64.0;
    
    // Calculate which "wedge" of the circle we are in
    float id = floor(a / sector_size + 0.5);
    
    // Remap angle to be local to that wedge (-0.5 to 0.5 of sector)
    float local_a = a - id * sector_size;
    
    // 4. Recover the Index (0 to 47)
    // We use modulo to wrap the ID back to 0-47 range
    int i = int(mod(id, 64.0)); 
    int j = i % 16; 
    
    // Fetch the height for THIS specific wedge
    float h = texelFetch(viz, ivec2(j, 0), 0).x;
    
    // 5. Reconstruct Position
    // In this folded space, the object is always at angle 0, distance 11.
    // We calculate p's position relative to that single object.
    vec2 local_pos = vec2(sin(local_a), cos(local_a)) * r;
    vec2 obj_pos = vec2(0.0, 11.0); // Object is at 0 rads, radius 11
    vec2 d_xz = local_pos - obj_pos;
    
    // 6. Handle Vertical Offset
    float y_pos = is_top ? y_offset : y_offset - (h * 2.5);
    
    // Construct the query point relative to the capsule center
    vec3 q = vec3(d_xz.x, p.y - y_pos, d_xz.y);
    
    return sdVerticalCapsule(q, h * 2.5, 0.25);
}

// --- Scene Map Function ---
float map(vec3 p) {
    float d = 1e10;
    
    // 1. Central Geometry (Unchanged)
    {
        vec3 q = p - vec3(0., 5., 0.);
        d = min(d, sdParallelogram(opRevolution(q, 10.), 0.5, 1., -.8));
    }
    {
        vec3 q = p - vec3(0., -5., 0.);
        d = min(d, sdParallelogram(opRevolution(q, 10.), 0.5, 1., .8));
    }
    {
        d = min(d, sdOctahedron(p, 4.0));
    }
    
    // 2. Optimized Rings (Replaces the loop)
    // Top Ring (Rotates Positive, Offset 0.75)
    d = min(d, opRing(p, 0.75, 1.0, true));
    
    // Bottom Ring (Rotates Negative, Offset -0.75)
    d = min(d, opRing(p, -0.75, -1.0, false));
    
    return d;
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
    vec3 light_pos = vec3(0.5, -3.0, p.z - 4.0);

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
    vec3 ro = vec3(3.0, 0.0, -10.);

    // Ray Direction
    // The UV becomes the XY direction, Z is forward (1.0)
    vec3 rd = normalize(vec3(uv, 1.0));

    // 3. Perform Raymarching
    float d = ray_march(ro, rd);

    // 4. Coloring
    vec3 col = vec3(0.);
	if(d < MAX_DIST) {
        // We hit something
        vec3 p = ro + rd * d;
		col = vec3(get_light(p)); 
	}

    // Output final color
    COLOR = vec4(col, 1.0);
}