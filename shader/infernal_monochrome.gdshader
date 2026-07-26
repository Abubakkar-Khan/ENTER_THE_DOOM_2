shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;

// --- MODERN ART PALETTE ---
// Strict 4-tone mapping: Black -> Red -> Yellow -> White
uniform float contrast : hint_range(0.5, 3.0, 0.01) = 0.4;
uniform float palette_shift : hint_range(-0.2, 0.2, 0.01) = 0.0; // Shifts the threshold of colors

// --- HEATWAVE & DISTORTION ---
uniform float heat_distortion : hint_range(0.0, 0.015, 0.001) = 0.004;
uniform float heat_speed : hint_range(0.0, 2.0, 0.01) = 0.8;

// --- STYLIZED CHROMATIC ---
// Splits edges into Red and Yellow for a fiery, misaligned print look
uniform float chromatic_split : hint_range(0.0, 0.008, 0.001) = 0.003;

// --- COOL DITHER & POSTERIZATION ---
uniform float dither_strength : hint_range(0.0, 0.15, 0.001) = 0.06;
uniform float color_bands : hint_range(4.0, 16.0, 1.0) = 8.0; // Lower = more graphic novel style

// --- MODERN VIGNETTE ---
uniform float vignette_strength : hint_range(0.0, 1.0, 0.01) = 0.65;
uniform float vignette_hardness : hint_range(1.0, 8.0, 0.1) = 4.5; // Higher = sharper, more graphic frame

// ============================================
// UTILS
// ============================================

float lum(vec3 c) { 
    return dot(c, vec3(0.299, 0.587, 0.114)); 
}

float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// 4x4 Bayer Matrix for that crisp, retro-modern dither
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
// HEATWAVE & CHROMATIC
// ============================================

vec2 heat_uv(vec2 uv, float time) {
    // Subtle, flowing heat distortion
    float wave = sin(uv.y * 15.0 + time * heat_speed) * 0.5 + 0.5;
    float noise_val = hash(uv * 50.0 + time * 0.1);
    return uv + vec2(wave * noise_val * heat_distortion, 0.0);
}

vec3 stylized_chromatic(sampler2D tex, vec2 uv, vec2 pixel_size) {
    if (chromatic_split < 0.001) return texture(tex, uv).rgb;
    
    // Calculate distance from center for edge-based splitting
    vec2 center = uv - 0.5;
    float dist = length(center);
    vec2 dir = normalize(center + 0.0001);
    
    // Split: Red shifts one way, Yellow (Green+Blue) shifts the other
    vec2 offset = dir * chromatic_split * dist * 2.0;
    
    float r = texture(tex, uv + offset).r;
    float g = texture(tex, uv - offset * 0.5).g;
    float b = texture(tex, uv - offset * 0.5).b;
    
    return vec3(r, g, b);
}

// ============================================
// MAIN
// ============================================

void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 pixel_size = SCREEN_PIXEL_SIZE;
    
    // 1. Apply Heatwave & Sample
    vec2 distorted_uv = heat_uv(uv, TIME);
    vec3 col = stylized_chromatic(screen_texture, distorted_uv, pixel_size);
    
    // 2. Base Luminance & Contrast
    float l = lum(col);
    l = (l - 0.5) * contrast + 0.5;
    l = clamp(l + palette_shift, 0.0, 1.0);
    
    // 3. Cool Dither + Posterization (Graphic Novel Effect)
    // Apply dither BEFORE banding to create organic, textured color boundaries
    float dither = bayer4(floor(uv * vec2(512.0, 512.0))) * dither_strength;
    l = clamp(l + dither, 0.0, 1.0);
    
    // Quantize into strict bands
    float banded_l = floor(l * (color_bands - 1.0) + 0.5) / (color_bands - 1.0);
    
    // 4. STRICT MODERN ART PALETTE MAPPING
    // Map the banded luminance to Black -> Red -> Yellow -> White
    vec3 c_black  = vec3(0.04, 0.01, 0.01); // Inky, warm black
    vec3 c_red    = vec3(0.85, 0.10, 0.05); // Deep, bloody crimson
    vec3 c_yellow = vec3(1.00, 0.75, 0.10); // Hot, saturated yellow
    vec3 c_white  = vec3(1.00, 0.95, 0.85); // Warm, aged white
    
    vec3 final_col;
    if (banded_l < 0.33) {
        final_col = mix(c_black, c_red, smoothstep(0.0, 0.33, banded_l));
    } else if (banded_l < 0.66) {
        final_col = mix(c_red, c_yellow, smoothstep(0.33, 0.66, banded_l));
    } else {
        final_col = mix(c_yellow, c_white, smoothstep(0.66, 1.0, banded_l));
    }
    
    // 5. PERFECT MODERN VIGNETTE
    // Uses a high-power curve for a sharp, graphic, framed look rather than a soft blur
    vec2 vignette_uv = uv * 2.0 - 1.0;
    // Slightly square off the vignette for a modern art frame feel
    float dist = pow(length(vignette_uv), vignette_hardness);
    float vig = 1.0 - dist * vignette_strength;
    final_col *= clamp(vig, 0.0, 1.0);
    
    // Force pure black in the extreme corners for maximum style
    if (vig < 0.1) {
        final_col = c_black;
    }

    COLOR = vec4(final_col, 1.0);
}