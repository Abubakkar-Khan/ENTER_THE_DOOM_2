shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// --- PASTEL PALETTE ---
uniform float saturation_boost : hint_range(0.0, 2.0, 0.01) = 1.3;
uniform float brightness_boost : hint_range(0.0, 1.0, 0.01) = 0.2;
uniform float pastel_strength : hint_range(0.0, 1.0, 0.01) = 0.75;

// --- BUBBLES & SPARKLES ---
uniform float bubble_scale : hint_range(2.0, 20.0, 0.1) = 8.0;
uniform float bubble_intensity : hint_range(0.0, 1.0, 0.01) = 0.3;
uniform float sparkle_density : hint_range(0.0, 1.0, 0.01) = 0.4;
uniform float sparkle_speed : hint_range(0.0, 3.0, 0.01) = 1.5;

// --- DREAMY MOTION ---
uniform float float_speed : hint_range(0.0, 2.0, 0.01) = 0.4;
uniform float wobble_amount : hint_range(0.0, 0.01, 0.001) = 0.003;

// --- RAINBOW SHIFT ---
uniform float rainbow_strength : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform float rainbow_speed : hint_range(0.0, 2.0, 0.01) = 0.3;

// --- SOFT GLOW ---
uniform float glow_strength : hint_range(0.0, 0.5, 0.01) = 0.15;
uniform float glow_softness : hint_range(0.0, 1.0, 0.01) = 0.6;

// --- DREAMY VIGNETTE ---
uniform float vignette_strength : hint_range(0.0, 1.0, 0.01) = 0.3;
uniform float vignette_color_shift : hint_range(0.0, 1.0, 0.01) = 0.5;

// ============================================
// UTILS
// ============================================

float lum(vec3 c) {
    return dot(c, vec3(0.299, 0.587, 0.114));
}

vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// ============================================
// BUBBLES (Soft, floating cells)
// ============================================

float bubbles(vec2 p, float time) {
    vec2 i = floor(p);
    vec2 f = fract(p);

    float min_dist = 1.0;

    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            vec2 neighbor = vec2(float(x), float(y));
            vec2 point = 0.5 + 0.5 * sin(time * 0.8 + 6.2831 * vec2(
                fract(sin(dot(i + neighbor, vec2(12.9898, 78.233))) * 43758.5453),
                fract(sin(dot(i + neighbor, vec2(63.7264, 10.873))) * 23421.6312)
            ));

            vec2 diff = neighbor + point - f;
            float dist = length(diff);
            min_dist = min(min_dist, dist);
        }
    }

    // Soft, rounded bubbles
    return smoothstep(0.0, 0.5, min_dist);
}

// ============================================
// SPARKLES (Twinkling stars)
// ============================================

float sparkle(vec2 uv, float time) {
    float s1 = fract(sin(dot(uv * 50.0, vec2(12.9898, 78.233))) * 43758.5453);
    float s2 = fract(sin(dot(uv * 50.0 + 100.0, vec2(63.7264, 10.873))) * 23421.6312);

    float twinkle = sin(time * sparkle_speed + s1 * 6.2831) * 0.5 + 0.5;
    twinkle = pow(twinkle, 8.0);

    return twinkle * step(1.0 - sparkle_density, s1 * s2);
}

// ============================================
// DREAMY WAVES
// ============================================

vec2 dreamy_wave(vec2 uv, float time) {
    float wave1 = sin(uv.y * 10.0 + time * float_speed) * 0.5 + 0.5;
    float wave2 = sin(uv.x * 8.0 + time * float_speed * 0.7) * 0.5 + 0.5;

    return vec2(
        sin(wave1 * 3.14159) * wobble_amount,
        cos(wave2 * 3.14159) * wobble_amount
    );
}

// ============================================
// MAIN
// ============================================

void fragment() {
    vec2 uv = SCREEN_UV;
    float time = TIME;

    // 1. DREAMY WAVY DISTORTION
    vec2 wave_offset = dreamy_wave(uv, time);
    vec2 distorted_uv = uv + wave_offset;

    // 2. SAMPLE WITH SOFT BLUR (Dreamy look)
    vec3 col = texture(screen_texture, distorted_uv).rgb;

    // Soft glow blur
    if (glow_strength > 0.01) {
        vec3 blur = vec3(0.0);
        float blur_size = glow_softness * 0.003;
        for (int i = 0; i < 8; i++) {
            float angle = float(i) * 0.785398; // PI/4
            vec2 offset = vec2(cos(angle), sin(angle)) * blur_size;
            blur += texture(screen_texture, distorted_uv + offset).rgb;
        }
        blur /= 8.0;
        col = mix(col, blur, glow_strength);
    }

    // 3. PASTEL COLOR GRADING
    // Boost brightness and saturation for that cute look
    col += brightness_boost;

    vec3 hsv = rgb2hsv(col);
    hsv.y = clamp(hsv.y * saturation_boost, 0.0, 1.0);
    hsv.z = clamp(hsv.z + brightness_boost * 0.3, 0.0, 1.0);
    col = hsv2rgb(hsv);

    // Pastel palette (soft pinks, lavenders, mints, peaches)
    vec3 pastel_pink = vec3(1.0, 0.75, 0.85);
    vec3 pastel_lavender = vec3(0.85, 0.75, 1.0);
    vec3 pastel_mint = vec3(0.75, 1.0, 0.9);
    vec3 pastel_peach = vec3(1.0, 0.85, 0.7);
    vec3 pastel_sky = vec3(0.75, 0.9, 1.0);

    // Map luminance to pastel colors
    float l = lum(col);
    vec3 pastel_col;
    if (l < 0.25) {
        pastel_col = mix(pastel_lavender, pastel_pink, smoothstep(0.0, 0.25, l));
    } else if (l < 0.5) {
        pastel_col = mix(pastel_pink, pastel_peach, smoothstep(0.25, 0.5, l));
    } else if (l < 0.75) {
        pastel_col = mix(pastel_peach, pastel_mint, smoothstep(0.5, 0.75, l));
    } else {
        pastel_col = mix(pastel_mint, pastel_sky, smoothstep(0.75, 1.0, l));
    }

    col = mix(col, pastel_col, pastel_strength);

    // 4. RAINBOW SHIFT (Magical color cycling)
    float rainbow = sin(uv.x * 5.0 + uv.y * 3.0 + time * rainbow_speed) * 0.5 + 0.5;
    vec3 rainbow_col = hsv2rgb(vec3(rainbow, 0.5, 1.0));
    col = mix(col, rainbow_col, rainbow_strength * 0.3);

    // 5. BUBBLES (Soft, floating patterns)
    vec2 bubble_uv = uv * bubble_scale;
    float bubble_pattern = bubbles(bubble_uv, time * float_speed);
    bubble_pattern = 1.0 - bubble_pattern; // Invert for bubble centers

    // Add soft pink/white highlights at bubble centers
    vec3 bubble_highlight = mix(pastel_pink, vec3(1.0), bubble_pattern);
    col = mix(col, bubble_highlight, bubble_pattern * bubble_intensity);

    // 6. SPARKLES (Twinkling stars)
    float spark = sparkle(uv, time);
    vec3 sparkle_col = mix(pastel_sky, vec3(1.0), 0.7);
    col += sparkle_col * spark * 0.5;

    // 7. DREAMY VIGNETTE
    vec2 vig_uv = uv * 2.0 - 1.0;
    float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
    vig_uv.x *= aspect;

    float vig_dist = length(vig_uv);
    float vig = 1.0 - smoothstep(0.6, 1.4, vig_dist) * vignette_strength;

    // Tint vignette to soft pink/lavender
    vec3 vig_color = mix(pastel_lavender, pastel_pink, vignette_color_shift);
    col = mix(col, vig_color * 0.8, 1.0 - vig);

    // 8. FINAL TOUCHES
    // Slight warm tint for extra cuteness
    col = mix(col, col * vec3(1.05, 0.98, 1.02), 0.3);

    // Ensure bright, happy colors
    col = clamp(col, 0.0, 1.2);

    COLOR = vec4(col, 1.0);
}