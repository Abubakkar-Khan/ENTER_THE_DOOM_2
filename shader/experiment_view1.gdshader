shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform vec2 target_resolution = vec2(320.0, 240.0);

uniform float color_levels : hint_range(2.0, 16.0, 1.0) = 8.0;
uniform float dither_strength : hint_range(0.0, 1.0, 0.01) = 0.3;
uniform float brightness : hint_range(0.5, 3.0, 0.01) = 1.4;
uniform float contrast : hint_range(0.5, 2.0, 0.01) = 1.15;
uniform float gamma : hint_range(0.5, 2.0, 0.01) = 0.9;

// Sin City accent
uniform float accent_intensity : hint_range(0.0, 1.0, 0.01) = 0.6;
uniform float accent_threshold : hint_range(0.1, 0.8, 0.01) = 0.3;

// Effects
uniform float chromatic : hint_range(0.0, 1.0, 0.01) = 0.15;
uniform float vignette_strength : hint_range(0.0, 0.8, 0.01) = 0.2;
uniform float heat_strength : hint_range(0.0, 1.0, 0.01) = 0.15;
uniform float heat_speed : hint_range(0.0, 2.0, 0.01) = 0.5;

float lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float bayer4(vec2 p) {
    int x = int(mod(p.x, 4.0));
    int y = int(mod(p.y, 4.0));
    int index = x + y * 4;
    float bayer[16] = float[](
        0.0, 8.0, 2.0, 10.0,
        12.0, 4.0, 14.0, 6.0,
        3.0, 11.0, 1.0, 9.0,
        15.0, 7.0, 13.0, 5.0
    );
    return (bayer[index] / 16.0) - 0.5;
}

float accent_mask(vec3 c) {
    float max_c = max(max(c.r, c.g), c.b);
    float min_c = min(min(c.r, c.g), c.b);
    float sat = max_c > 0.001 ? (max_c - min_c) / max_c : 0.0;
    
    float blood = smoothstep(0.15, 0.5, c.r)
                * (1.0 - smoothstep(0.0, 0.25, c.g))
                * (1.0 - smoothstep(0.0, 0.25, c.b))
                * smoothstep(0.1, 0.5, sat);
                
    float warm = smoothstep(0.4, 1.0, max_c)
               * smoothstep(0.0, 0.3, c.r - c.b)
               * smoothstep(0.05, 0.35, sat);
               
    return clamp(blood + warm * 0.4, 0.0, 1.0);
}

vec3 sin_city_grade(vec3 c, float accent) {
    // Start from original color luminance, don't crush
    float l = lum(c);
    
    // Warm tinted B&W — NOT crushed to black
    vec3 bw = vec3(l * 1.1, l * 0.98, l * 0.92);
    
    // Crimson accent
    vec3 accent_col = vec3(0.95, 0.06, 0.03);
    
    // Gentle blend
    float t = smoothstep(0.0, accent_threshold, accent) * accent_intensity;
    return mix(bw, accent_col, t);
}

vec2 heat_offset(vec2 uv, float time) {
    vec2 fuv = uv * 8.0 + vec2(0.0, time * heat_speed);
    float d = noise(fuv) * 0.6 + noise(fuv * 2.0 + vec2(5.2, 1.3)) * 0.4;
    return vec2((d - 0.5) * 0.3, (d - 0.5) * 0.9) * heat_strength * 0.003;
}

vec3 sample_chromatic(sampler2D tex, vec2 uv, float amount) {
    if (amount < 0.01) return texture(tex, uv).rgb;
    vec2 c = uv * 2.0 - 1.0;
    float edge = smoothstep(0.0, 1.0, length(c));
    if (edge < 0.01) return texture(tex, uv).rgb;
    vec2 off = normalize(c + 0.0001) * amount * 0.001 * edge;
    return vec3(texture(tex, uv + off * 1.0).r,
                texture(tex, uv + off * 0.5).g,
                texture(tex, uv - off * 0.3).b);
}

vec3 apply_vignette(vec3 c, vec2 uv, float strength, float radius) {
    return c * (1.0 - smoothstep(radius * 0.5, radius, length(uv * 2.0 - 1.0)) * strength);
}

void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 pixel = floor(uv * target_resolution);
    vec2 block_uv = pixel / target_resolution;
    
    // Sample scene
    vec2 heat = heat_offset(block_uv, TIME);
    vec3 col = sample_chromatic(screen_texture, block_uv + heat, chromatic);
    
    // Detect blood/lava accents
    float accent = accent_mask(col);
    
    // Grade: warm B&W world + crimson accents (NO shadow crush)
    col = sin_city_grade(col, accent);
    
    // Brightness / contrast / gamma
    col = pow(col, vec3(gamma));
    col = (col - 0.5) * contrast + 0.5;
    col *= brightness;
    
    // Tiny film noise
    col += (hash(pixel + fract(TIME * 0.1)) - 0.5) * 0.012;
    
    // Very subtle sky dim
    col *= mix(0.96, 1.0, uv.y);
    
    // Dither + quantize on luminance only
    float l = lum(col);
    float dither = bayer4(pixel) * dither_strength;
    l += dither * smoothstep(0.05, 0.95, l);
    
    float stepped = floor(l * (color_levels - 1.0) + 0.5) / (color_levels - 1.0);
    stepped = clamp(stepped, 0.0, 1.0);
    
    // Scale color to new luminance safely
    float orig_l = max(lum(col), 0.001);
    col *= clamp(stepped / orig_l, 0.0, 3.0);
    
    // Clamp to infernal palette (but NOT crushed)
    col = clamp(col, vec3(0.0), vec3(1.0, 0.55, 0.4));
    
    // Vignette
    col = apply_vignette(col, uv, vignette_strength, 1.3);
    
    COLOR = vec4(col, 1.0);
}