shader_type canvas_item;

// --- Uniforms ---

global uniform sampler2D viz;
uniform vec3 camera_location = vec3(3.0, 0.28, -10.);

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

float sdTorus( vec3 p, vec2 t )
{
	vec2 q = vec2(length(p.xz)-t.x,p.y);
	return length(q)-t.y;
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
    float y_pos = is_top ? y_offset : y_offset - (h * 3.0);
    
    // Construct the query point relative to the capsule center
    vec3 q = vec3(d_xz.x, p.y - y_pos, d_xz.y);
    
    return sdVerticalCapsule(q, h * 3., 0.1);
}

// --- Rotation Matrices ---
mat3 rotateY(float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return mat3(
        vec3(c, 0.0, s),
        vec3(0.0, 1.0, 0.0),
        vec3(-s, 0.0, c)
    );
}

mat3 rotateX(float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return mat3(
        vec3(1.0, 0.0, 0.0),
        vec3(0.0, c, -s),
        vec3(0.0, s, c)
    );
}

// --- Scene Map Function ---
float map(vec3 p, out int object_id) {
    float d = 1e10;
    object_id = 0;
    
    // 1. Central Geometry (Unchanged)
    {
        vec3 q = p - vec3(0., 5., 0.);
        float dist = sdParallelogram(opRevolution(q, 10.), 0.5, 1., -.8);
		if(dist < d) {
			d = dist;
			object_id = 1;
		}
    }
    {
        vec3 q = p - vec3(0., -5., 0.);
        float dist = sdParallelogram(opRevolution(q, 10.), 0.5, 1., .8);
		if(dist < d) {
			d = dist;
			object_id = 2;
		}
    }
    {
        // Slowly rotating octahedron
        vec3 q = p;
        q *= rotateY(TIME * 0.3); // Rotate around Y axis
        q *= rotateX(TIME * 0.2);  // Rotate around X axis for more interesting motion
		float dist = sdOctahedron(q, 3.0);
		if(dist < d) {
			d = dist;
			object_id = 3;
		}
    }
    
    // 2. Optimized Rings (Replaces the loop)
    // Top Ring (Rotates Positive, Offset 0.75)
	{
		float dist = opRing(p, 0.5, 1.0, true);
		if(dist < d) {
			d = dist;
			object_id = 4;
		}
	}
    
    // Bottom Ring (Rotates Negative, Offset -0.75)
	{
		float dist = opRing(p, -0.5, -1.0, false);
		if(dist < d) {
			d = dist;
			object_id = 5;
		}
	}
    
    return d;
}

// --- Raymarcher ---

// Casts a ray from 'ro' (Ray Origin) in direction 'rd' (Ray Direction)
float ray_march(vec3 ro, vec3 rd, out int hit_object_id) {
    float dO = 0.0; // Distance Origin (total distance traveled)
    hit_object_id = 0;

    for(int i = 0; i < MAX_STEPS; i++) {
        vec3 p = ro + rd * dO; // Current position along the ray
        float dS = map(p, hit_object_id);     // Distance to closest Surface

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
	int dummy;
    float d = map(p, dummy);
    vec2 e = vec2(0.01, 0.0);

    vec3 n = d - vec3(
        map(p - e.xyy, dummy),
        map(p - e.yxy, dummy),
        map(p - e.yyx, dummy)
    );

    return normalize(n);
}

// Calculates lighting with specular base
vec2 get_light(vec3 p, vec3 view_dir) {
    // Light position (relative to camera or fixed in world)
    vec3 light_pos = vec3(0.5, -3.0, p.z - 4.0);

    vec3 l = normalize(light_pos - p);
    vec3 n = get_normal(p);

    // Diffuse component (Lambertian)
    float dif = clamp(dot(n, l), 0.0, 1.0);
    
    // Specular component (Blinn-Phong base)
    vec3 h = normalize(l + view_dir); // Half vector
    float base_spec = clamp(dot(n, h), 0.0, 1.0);
    
    return vec2(dif, base_spec);
}

// Convert HSL to RGB
vec3 hsl_to_rgb(float h, float s, float l) {
    float c = (1.0 - abs(2.0 * l - 1.0)) * s;
    float x = c * (1.0 - abs(mod(h * 6.0, 2.0) - 1.0));
    float m = l - c / 2.0;
    
    vec3 rgb;
    if (h < 1.0/6.0) rgb = vec3(c, x, 0.0);
    else if (h < 2.0/6.0) rgb = vec3(x, c, 0.0);
    else if (h < 3.0/6.0) rgb = vec3(0.0, c, x);
    else if (h < 4.0/6.0) rgb = vec3(0.0, x, c);
    else if (h < 5.0/6.0) rgb = vec3(x, 0.0, c);
    else rgb = vec3(c, 0.0, x);
    
    return rgb + m;
}

void fragment() {
    // 1. Aspect Ratio Correction
    // SCREEN_PIXEL_SIZE is vec2(1.0/width, 1.0/height)
    // We center UVs to -0.5 to 0.5 first
    vec2 uv = UV - 0.5;

    // Fix aspect ratio so X is wider than Y on landscape screens
    uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;

    int object_id;

    // 2. Camera Setup
    // Ray Origin (Camera Position)
    vec3 ro = camera_location;

    // Ray Direction
    // The UV becomes the XY direction, Z is forward (1.0)
    vec3 rd = normalize(vec3(uv, 1.0));

    // 3. Perform Raymarching
    float d = ray_march(ro, rd, object_id);

    vec3 bg_color = hsl_to_rgb(0.58, 0.4, 0.08);
    
    vec3 col = bg_color;
	if(d < MAX_DIST) {
        // We hit something
        vec3 p = ro + rd * d;
        vec2 lighting = get_light(p, -rd); // Pass view direction for specular
        float diffuse = lighting.x;
        float base_spec = lighting.y;
        
        // Material properties
        float hue = 0.55;
        float sat = 0.5;
        float lightness = 0.5;
        float shininess = 64.0;
        float spec_intensity = 0.8;
        vec3 specular_color = vec3(1.0);
        
        if (object_id == 1 || object_id == 2) {
            // Parallelograms (Outer rings / walls)
            hue = mix(0.65, 0.60, (p.y + 5.0) / 10.0);
            sat = mix(0.4, 0.6, diffuse);
            lightness = mix(0.1, 0.25, diffuse);
            shininess = 32.0;
            spec_intensity = 0.4;
            specular_color = hsl_to_rgb(0.60, 0.8, 0.8);
        } else if (object_id == 3) {
            // Octahedron (Center piece)
            hue = mix(0.65, 0.70, (p.y + 3.0) / 6.0); 
            sat = mix(0.6, 0.9, diffuse);
            lightness = mix(0.2, 0.6, diffuse);
            shininess = 128.0;
            spec_intensity = 1.0;
            specular_color = hsl_to_rgb(0.90, 0.9, 0.9);
        } else if (object_id == 4 || object_id == 5) {
            // Visualizer Rings (Audio reactive pills)
            hue = mix(0.50, 0.55, (p.y + 5.0) / 10.0);
            sat = mix(0.5, 0.8, diffuse);
            lightness = mix(0.2, 0.5, diffuse);
            shininess = 64.0;
            spec_intensity = 0.9;
            specular_color = hsl_to_rgb(0.52, 0.8, 0.9);
        }
        
        float specular = pow(base_spec, shininess);
        
        vec3 surface_color = hsl_to_rgb(hue, sat, lightness);
        surface_color += specular_color * specular * spec_intensity;
        
        // Depth fog: Mix surface color with background based on distance
        float fog_factor = smoothstep(0.0, MAX_DIST * 0.7, d);
        col = mix(surface_color, bg_color, fog_factor);
	}

    // Output final color
    COLOR = vec4(col, 1.0);
}