shader_type spatial;

uniform float height = 64.0;
uniform sampler2D color_gradient;

// --- ROCK DETAIL ---
// Plug your uploaded blue/purple normal map here
uniform sampler2D rock_normal_map : hint_normal;

// Controls how often the pattern repeats (meters). 
// 10.0 means the texture tiles every 10 meters.
uniform float rock_tile_size = 10.0; 

// Strength of the rocky ripples
uniform float rock_intensity : hint_range(0.0, 2000.0) = 1.0;

void fragment() {
    // 1. Get the World Position for tiling
    // This ignores UVs to prevent the "stretched pixel" look
    vec4 world_vertex = INV_VIEW_MATRIX * vec4(VERTEX, 1.0);
    vec3 world_pos = (inverse(MODEL_MATRIX) * world_vertex).xyz;
    
    // 2. Base Color Gradient (Height-based)
    float gradient_uv = (world_pos.y / height) + 0.5;
    ALBEDO = texture(color_gradient, vec2(gradient_uv)).rgb;

    // 3. Triplanar Normal Mapping
    // We calculate weights to blend the texture smoothly on slopes
    vec3 blending = abs(NORMAL);
    blending /= (blending.x + blending.y + blending.z);

    // Sample the texture from 3 axes based on World Position
    vec3 x_norm = texture(rock_normal_map, world_pos.zy / rock_tile_size).rgb;
    vec3 y_norm = texture(rock_normal_map, world_pos.xz / rock_tile_size).rgb;
    vec3 z_norm = texture(rock_normal_map, world_pos.xy / rock_tile_size).rgb;
    
    // Blend the samples together
    vec3 final_rock_normal = x_norm * blending.x + y_norm * blending.y + z_norm * blending.z;
    
    // Apply to the terrain
    NORMAL_MAP = final_rock_normal;
    NORMAL_MAP_DEPTH = rock_intensity;
}