shader_type canvas_item;

// ============================================================================
// INFERNAL FPS — CINEMATIC POST-PROCESS
// Godot 4.5 | Fullscreen ColorRect | Forward+
// ============================================================================
// A scene-aware, color-first post-process for an infernal low-poly FPS.
// 
// Philosophy: Beautiful palette first, retro aesthetic second.
// The shader reads the scene (detail, temperature, luminance) and treats
// pixels differently based on what they are — not as a uniform filter.
//
// Pipeline:
//   Screen Sample → Heat Distortion → Lava Glow → Linear Space →
//   Infernal Color Grade → Palette Compression → Shadow Tint →
//   Contrast → Saturation → Selective Quantization → Dither →
//   Unsharp Mask → sRGB → Eye Pulse → Output
// ============================================================================

// ============================================================================
// UNIFORMS
// ============================================================================

// Color grading
uniform float u_contrast : hint_range(0.5, 2.0, 0.01) = 1.15;
uniform float u_saturation : hint_range(0.0, 2.0, 0.01) = 1.08;
uniform float u_palette_compress : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform float u_shadow_tint : hint_range(0.0, 1.0, 0.01) = 0.35;

// Quantization & dither
uniform float u_color_levels : hint_range(8.0, 48.0, 1.0) = 22.0;
uniform float u_dither_strength : hint_range(0.0, 1.0, 0.01) = 0.25;

// Heat distortion (FBM-based, lava-only)
uniform float u_heat_strength : hint_range(0.0, 2.0, 0.01) = 0.6;
uniform float u_heat_speed : hint_range(0.0, 4.0, 0.01) = 1.2;
uniform float u_heat_scale : hint_range(4.0, 32.0, 0.01) = 14.0;

// Selective lava glow
uniform float u_glow_intensity : hint_range(0.0, 2.0, 0.01) = 0.4;
uniform float u_glow_radius : hint_range(1.0, 8.0, 0.01) = 2.5;

// Edge sharpen (post-quantization clarity recovery)
uniform float u_sharpen : hint_range(0.0, 1.0, 0.01) = 0.25;

// Dynamic eye (subconscious effect when looking at the giant eye)
uniform vec2 u_eye_position = vec2(0.5, 0.3);
uniform float u_eye_intensity : hint_range(0.0, 1.0, 0.01) = 1.0;

// Screen texture
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// ============================================================================
// UTILITY
// ============================================================================

vec3 srgb_to_linear(vec3 c) { return pow(c, vec3(2.2)); }
vec3 linear_to_srgb(vec3 c) { return pow(c, vec3(1.0 / 2.2)); }
vec3 clamp3(vec3 c) { return clamp(c, vec3(0.0), vec3(1.0)); }
float luminance(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

// ============================================================================
// NOISE & FBM
// ============================================================================

float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    mat2 rot = mat2(vec2(0.5, 0.5), vec2(-0.5, 0.5));
    for (int i = 0; i < 4; i++) {
        v += a * noise(p);
        p = rot * p * 2.0 + vec2(100.0);
        a *= 0.5;
    }
    return v;
}

// ============================================================================
// MASKS
// ============================================================================

// Detects bright warm pixels (lava, fire). Returns 0 for cool/dark pixels.
float lava_mask(vec3 c) {
    float warmth = c.r * 0.5 + c.g * 0.3 - c.b * 0.2;
    float brightness = max(max(c.r, c.g), c.b);
    return smoothstep(0.2, 0.5, warmth * brightness);
}

// ============================================================================
// HEAT DISTORTION
// ============================================================================

// Real rising hot air using layered FBM noise.
// Only affects pixels that are themselves lava (hot air rises from hot surfaces).
// Pillars, weapons, and UI remain completely stable.
vec2 heat_offset(vec2 uv, vec3 base_color, float time) {
    float mask = lava_mask(base_color);
    if (mask < 0.01) return vec2(0.0);

    // Scroll upward in UV space (negative Y direction on screen)
    vec2 fbm_uv = uv * u_heat_scale + vec2(0.0, time * u_heat_speed);
    float f1 = fbm(fbm_uv);
    float f2 = fbm(fbm_uv + vec2(5.2, 1.3));

    // Mostly vertical displacement (rising heat) with slight horizontal turbulence
    vec2 off = vec2((f1 - 0.5) * 0.3, (f2 - 0.5) * 1.0);
    return off * u_heat_strength * mask * 0.005;
}

// ============================================================================
// DYNAMIC EYE
// ============================================================================

// Returns 1.0 when the player is looking directly at the eye, 0.0 when looking away.
// The game should update u_eye_position each frame with the eye's screen-space UV.
float eye_proximity(vec2 uv, vec2 eye_uv) {
    float d = length(uv - eye_uv);
    return (1.0 - smoothstep(0.0, 0.4, d)) * u_eye_intensity;
}

// Subtle subconscious UV jitter when facing the eye. Max offset < 0.001 UV.
vec2 eye_jitter(vec2 uv, float time, float prox) {
    if (prox < 0.001) return vec2(0.0);
    float jx = sin(time * 3.1 + uv.y * 6.0);
    float jy = cos(time * 2.7 + uv.x * 6.0);
    return vec2(jx, jy) * prox * 0.0008;
}

// ============================================================================
// COLOR PROCESSING
// ============================================================================

// Cinematic 4-stop infernal color grade:
//   Shadows   → Dark crimson
//   Midtones  → Deep warm red
//   Highlights→ Orange
//   Lava      → Yellow-white
vec3 infernal_grade(vec3 c) {
    float lum = luminance(c);
    float max_c = max(max(c.r, c.g), c.b);

    // Shadows: shift toward warm crimson (not neutral gray)
    float shadow = 1.0 - smoothstep(0.0, 0.18, lum);
    c += vec3(0.07, 0.008, 0.015) * shadow;

    // Midtones: deepen reds, warm greens toward orange
    float mid = smoothstep(0.1, 0.4, lum) * (1.0 - smoothstep(0.4, 0.8, lum));
    c.r += mid * 0.04;
    c.g = mix(c.g, c.g * 0.75 + c.r * 0.2, mid);

    // Highlights: push toward orange
    float high = smoothstep(0.5, 1.0, lum);
    c.r += high * 0.03;
    c.g += high * 0.06;
    c.b -= high * 0.12;

    // Extreme highlights (lava): yellow-white hot
    float lava = smoothstep(0.7, 1.0, max_c);
    c = mix(c, vec3(1.0, 0.82, 0.35), lava * 0.25);

    // Global blue suppression — blues become warm shadows
    c.b *= 0.55;

    return clamp3(c);
}

// Artistically compress the palette toward the infernal axis:
// Black → Dark Red → Crimson → Orange → Yellow → White
// Blues disappear. Greens warm up. Reds stay detailed.
vec3 palette_compress(vec3 c, float strength) {
    float lum = luminance(c);
    float blue = c.b;

    // Kill blues, bleed them into warm reds in shadow areas
    c.b = mix(c.b, c.b * 0.2, strength);
    c.r += blue * 0.12 * strength * (1.0 - lum);

    // Warm greens toward yellow-orange
    c.g = mix(c.g, c.g * 0.65 + c.r * 0.25, strength);

    // Subtle pull toward the infernal red-orange axis
    vec3 axis = normalize(vec3(1.0, 0.35, 0.05));
    float lum2 = luminance(c);
    float sat = length(c - vec3(lum2));
    vec3 pulled = axis * sat + vec3(lum2);
    c = mix(c, pulled, strength * 0.15);

    return clamp3(c);
}

// Shift shadow blacks toward dark crimson instead of neutral gray.
// The world feels warm and infernal, never cold or muddy.
vec3 shadow_tint(vec3 c, float strength) {
    float lum = luminance(c);
    float shadow = 1.0 - smoothstep(0.0, 0.22, lum);
    vec3 tint = vec3(0.06, 0.005, 0.01);
    return c + tint * shadow * strength;
}

// Proper midpoint contrast in linear space
vec3 apply_contrast(vec3 c, float contrast) {
    return (c - 0.5) * contrast + 0.5;
}

// Luminance-preserving saturation
vec3 apply_saturation(vec3 c, float sat) {
    float lum = luminance(c);
    return mix(vec3(lum), c, sat);
}

// ============================================================================
// DITHER
// ============================================================================

// 4x4 Bayer ordered dither. Almost invisible — only smooths banding.
float bayer(ivec2 p) {
    int x = p.x % 4;
    int y = p.y % 4;
    int v = 0;
    if (x == 0) {
        v = (y == 0) ? 0 : (y == 1) ? 8 : (y == 2) ? 2 : 10;
    } else if (x == 1) {
        v = (y == 0) ? 12 : (y == 1) ? 4 : (y == 2) ? 14 : 6;
    } else if (x == 2) {
        v = (y == 0) ? 3 : (y == 1) ? 11 : (y == 2) ? 1 : 9;
    } else {
        v = (y == 0) ? 15 : (y == 1) ? 7 : (y == 2) ? 13 : 5;
    }
    return float(v) / 16.0;
}

vec3 apply_dither(vec3 c, vec2 pixel, float strength, float levels) {
    float d = bayer(ivec2(pixel) % ivec2(4)) - 0.5;
    return c + vec3(d * strength / levels);
}

// ============================================================================
// MAIN
// ============================================================================

void fragment() {
    vec2 uv = UV;

    // --- Dynamic Eye: subtle UV jitter when looking at the eye ---
    float eye_prox = eye_proximity(uv, u_eye_position);
    uv += eye_jitter(uv, TIME, eye_prox);

    // --- Base sample for heat mask and detail detection ---
    // Sampled at original UVs so masks are consistent regardless of distortion
    vec3 base = texture(screen_texture, uv).rgb;

    // --- Heat distortion: only lava pixels get offset UVs ---
    vec2 heat_off = heat_offset(uv, base, TIME);
    vec2 sample_uv = uv + heat_off;

    // --- Sample center and 4 neighbors (shared for glow, blur, sharpen) ---
    vec3 center = texture(screen_texture, sample_uv).rgb;
    vec2 px = SCREEN_PIXEL_SIZE * u_glow_radius;
    vec3 n_r = texture(screen_texture, sample_uv + vec2(px.x, 0.0)).rgb;
    vec3 n_l = texture(screen_texture, sample_uv + vec2(-px.x, 0.0)).rgb;
    vec3 n_u = texture(screen_texture, sample_uv + vec2(0.0, px.y)).rgb;
    vec3 n_d = texture(screen_texture, sample_uv + vec2(0.0, -px.y)).rgb;

    // --- Convert to linear space for all color operations ---
    vec3 lin_c = srgb_to_linear(center);
    vec3 lin_r = srgb_to_linear(n_r);
    vec3 lin_l = srgb_to_linear(n_l);
    vec3 lin_u = srgb_to_linear(n_u);
    vec3 lin_d = srgb_to_linear(n_d);

    // --- Lava Glow: selective warm bleed from bright neighbors ---
    // Only bright warm pixels bleed. Dark pixels receive the glow.
    float lr = lava_mask(n_r);
    float ll = lava_mask(n_l);
    float lu = lava_mask(n_u);
    float ld = lava_mask(n_d);
    vec3 glow = lin_r * lr + lin_l * ll + lin_u * lu + lin_d * ld;
    float glow_w = lr + ll + lu + ld;
    vec3 glow_color = glow_w > 0.001 ? glow / glow_w : lin_c;
    float center_lava = lava_mask(center);
    float glow_blend = glow_w * 0.25 * u_glow_intensity * (1.0 - center_lava * 0.6);
    vec3 color = mix(lin_c, glow_color, glow_blend);

    // --- Detail mask: high contrast edges = gameplay-critical (weapon, enemies) ---
    // Flat surfaces (terrain, pillar faces, lava) = low detail = quantize more
    float detail = length(fwidth(base));
    float detail_mask = smoothstep(0.0, 0.06, detail);

    // --- Cinematic infernal color pipeline ---
    color = infernal_grade(color);
    color = palette_compress(color, u_palette_compress);
    color = shadow_tint(color, u_shadow_tint);
    color = apply_contrast(color, u_contrast);
    color = apply_saturation(color, u_saturation + eye_prox * 0.04);

    // --- Selective quantization: smooth on edges, retro on flat surfaces ---
    float levels = mix(u_color_levels, 48.0, detail_mask);
    color = apply_dither(color, FRAGCOORD.xy, u_dither_strength, levels);
    color = round(color * levels) / levels;

    // --- Unsharp mask: restore crisp edges after quantization ---
    // Only applies where detail_mask is high (edges), never on flat noise
    vec3 blur = (lin_r + lin_l + lin_u + lin_d) * 0.25;
    vec3 sharp = color + (color - blur) * u_sharpen * detail_mask;
    color = mix(color, sharp, u_sharpen * detail_mask);

    // --- Return to sRGB for output ---
    color = linear_to_srgb(color);

    // --- Subtle eye pulse (subconscious brightness breathing, < 3%) ---
    color *= 1.0 + sin(TIME * 2.5) * eye_prox * 0.03;

    COLOR = vec4(clamp3(color), 1.0);
}
