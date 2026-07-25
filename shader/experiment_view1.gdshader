shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;

// --- Exposure ---
uniform float brightness : hint_range(0.5, 2.0, 0.01) = 0.95;
uniform float contrast : hint_range(0.8, 2.0, 0.01) = 1.15;
uniform float gamma : hint_range(0.5, 2.0, 0.01) = 0.88;
uniform float shadow_lift : hint_range(0.0, 0.15, 0.01) = 0.04;

// --- Sin City Selective Color ---
uniform float desaturate : hint_range(0.0, 1.0, 0.01) = 0.75;
uniform float accent_intensity : hint_range(0.0, 1.0, 0.01) = 0.7;
uniform float accent_threshold : hint_range(0.05, 0.6, 0.01) = 0.18;

// --- Organic Bleed ---
uniform float bleed_intensity : hint_range(0.0, 0.4, 0.01) = 0.12;
uniform float bleed_radius : hint_range(1.0, 6.0, 0.01) = 2.5;

// --- Film Grain ---
uniform float grain_strength : hint_range(0.0, 0.06, 0.001) = 0.018;
uniform float grain_size : hint_range(800.0, 2500.0, 1.0) = 1400.0;

// --- Chromatic & Heat ---
uniform float chromatic : hint_range(0.0, 0.5, 0.01) = 0.08;
uniform float heat_strength : hint_range(0.0, 0.3, 0.01) = 0.06;
uniform float heat_speed : hint_range(0.0, 1.0, 0.01) = 0.35;

// --- Vignette ---
uniform float vignette_strength : hint_range(0.0, 0.5, 0.01) = 0.22;
uniform float vignette_radius : hint_range(0.8, 2.0, 0.01) = 1.45;

// --- Dither ---
uniform float dither_strength : hint_range(0.0, 0.15, 0.01) = 0.045;
uniform float color_levels : hint_range(48.0, 96.0, 1.0) = 72.0;

// ============================================
// UTILS
// ============================================

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

// ============================================
// BAYER 4x4 DITHER
// ============================================

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

// ============================================
// ACCENT DETECTION (nuanced, not just red)
// ============================================

float accent_mask(vec3 c) {
    float max_c = max(max(c.r, c.g), c.b);
    float min_c = min(min(c.r, c.g), c.b);
    float sat = max_c > 0.001 ? (max_c - min_c) / max_c : 0.0;
    
    // Blood red: deep saturated red, low green/blue
    float blood = smoothstep(0.2, 0.5, c.r)
                * (1.0 - smoothstep(0.0, 0.2, c.g))
                * (1.0 - smoothstep(0.0, 0.2, c.b))
                * smoothstep(0.12, 0.5, sat);
    
    // Warm fire: orange-red highlights
    float fire = smoothstep(0.45, 0.9, c.r)
               * smoothstep(0.05, 0.35, c.g)
               * (1.0 - smoothstep(0.15, 0.4, c.b))
               * smoothstep(0.3, 0.8, max_c);
               
    // Warm highlights: golden/orange key lights
    float warm = smoothstep(0.55, 1.0, max_c)
               * smoothstep(0.0, 0.3, c.r - c.b)
               * smoothstep(0.08, 0.4, sat);
    
    return clamp(blood * 1.2 + fire * 0.8 + warm * 0.3, 0.0, 1.0);
}

// ============================================
// SAMPLING
// ============================================

vec2 heat_offset(vec2 uv, float time) {
    vec2 fuv = uv * 5.0 + vec2(0.0, time * heat_speed);
    float d = noise(fuv) * 0.6 + noise(fuv * 1.5 + vec2(4.1, 6.3)) * 0.4;
    return vec2((d - 0.5) * 0.35, (d - 0.5) * 0.9) * heat_strength * 0.002;
}

vec3 sample_chromatic(sampler2D tex, vec2 uv, float amount) {
    if (amount < 0.005) return texture(tex, uv).rgb;
    vec2 c = uv * 2.0 - 1.0;
    float edge = smoothstep(0.0, 1.0, length(c));
    if (edge < 0.01) return texture(tex, uv).rgb;
    vec2 off = normalize(c + 0.0001) * amount * 0.0006 * edge;
    return vec3(texture(tex, uv + off * 1.0).r,
                texture(tex, uv + off * 0.5).g,
                texture(tex, uv - off * 0.3).b);
}

// ============================================
// ORGANIC BLEED (soft directional glow)
// ============================================

vec3 organic_bleed(sampler2D tex, vec2 uv, vec2 sp, float time) {
    vec3 bleed = vec3(0.0);
    float weight = 0.0;
    
    // 6-tap asymmetric bleed for organic feel
    vec2 offsets[6] = vec2[](
        vec2(1.0, 0.3), vec2(-0.8, -0.2),
        vec2(0.2, 1.1), vec2(-0.3, -0.9),
        vec2(0.6, 0.6), vec2(-0.5, -0.5)
    );
    
    for (int i = 0; i < 6; i++) {
        float t = time * 0.4 + float(i) * 1.7;
        vec2 off = offsets[i] * sp * bleed_radius * (1.0 + sin(t) * 0.1);
        vec3 samp = texture(tex, uv + off).rgb;
        float mask = accent_mask(samp);
        
        // Only bleed from bright accents
        float bright = smoothstep(0.3, 0.8, lum(samp));
        float w = mask * bright;
        
        bleed += samp * w;
        weight += w;
    }
    
    if (weight < 0.001) return vec3(0.0);
    return (bleed / weight) * bleed_intensity;
}

// ============================================
// FILM GRAIN (temporal, organic)
// ============================================

float film_grain(vec2 uv, float time) {
    vec2 p = uv * grain_size;
    float g1 = hash(p + fract(time * 0.047) * 100.0);
    float g2 = hash(p * 1.3 + fract(time * 0.089) * 67.0);
    float g = (g1 + g2 * 0.5) / 1.5;
    return (g - 0.5) * grain_strength;
}

// ============================================
// VIGNETTE
// ============================================

vec3 apply_vignette(vec3 c, vec2 uv, float strength, float radius) {
    float dist = length(uv * 2.0 - 1.0);
    float v = 1.0 - smoothstep(radius * 0.4, radius, dist) * strength;
    return c * v;
}

// ============================================
// MAIN
// ============================================

void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 sp = SCREEN_PIXEL_SIZE;
    
    // Full res sampling with subtle heat + chromatic
    vec2 heat = heat_offset(uv, TIME);
    vec3 col = sample_chromatic(screen_texture, uv + heat, chromatic);
    
    // Detect accents
    float accent = accent_mask(col);
    
    // --- BASE: Desaturate to warm B&W, but KEEP detail ---
    float l = lum(col);
    
    // Warm-tinted monochrome (not pure gray)
    vec3 gray = vec3(l * 1.02, l * 0.96, l * 0.9);
    col = mix(col, gray, desaturate);
    
    // --- ACCENT: Selective crimson (not overwhelming) ---
    // Deep blood red for dark accents, bright scarlet for highlights
    float accent_lum = lum(col);
    vec3 deep_red = vec3(0.65, 0.02, 0.01);
    vec3 bright_red = vec3(0.95, 0.12, 0.05);
    vec3 accent_col = mix(deep_red, bright_red, smoothstep(0.3, 0.7, accent_lum));
    
    float accent_blend = smoothstep(0.0, accent_threshold, accent) * accent_intensity;
    col = mix(col, accent_col, accent_blend);
    
    // --- ORGANIC BLEED from bright accents ---
    vec3 bleed = organic_bleed(screen_texture, uv + heat, sp, TIME);
    col += bleed * accent_blend;
    
    // --- EXPOSURE: Darker but lifted shadows ---
    col = pow(max(col, vec3(0.0)), vec3(gamma));
    col = (col - 0.5) * contrast + 0.5;
    col += shadow_lift;  // Prevent crushed blacks
    col *= brightness;
    
    // --- FILM GRAIN ---
    col += film_grain(uv, TIME);
    
    // --- DITHER + SOFT QUANTIZE ---
    // Bayer dither on luminance only
    float l2 = lum(col);
    float dither = bayer4(floor(uv * vec2(800.0, 600.0))) * dither_strength;
    l2 += dither * smoothstep(0.05, 0.95, l2);
    
    float stepped = floor(l2 * (color_levels - 1.0) + 0.5) / (color_levels - 1.0);
    stepped = clamp(stepped, 0.0, 1.0);
    
    // Scale color to quantized luminance safely
    float orig_l = max(lum(col), 0.001);
    col *= clamp(stepped / orig_l, 0.0, 2.0);
    
    // Clamp (allow some blue in shadows for film look)
    col = clamp(col, vec3(0.0), vec3(1.0, 0.65, 0.5));
    
    // --- VIGNETTE ---
    col = apply_vignette(col, uv, vignette_strength, vignette_radius);
    
    COLOR = vec4(col, 1.0);
}