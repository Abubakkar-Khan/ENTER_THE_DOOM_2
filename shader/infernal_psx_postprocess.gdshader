shader_type canvas_item;

// ============================================================================
// INFERNAL PSX POST-PROCESSING SHADER
// Godot 4.5 | Fullscreen ColorRect | Forward+ Rendering
// ============================================================================
// Subtle atmospheric post-processing for an infernal FPS.
// Inspired by Devil Daggers, Post Void, ULTRAKILL, SIGNALIS, Iron Lung, DUSK.
// 
// Pipeline: Screen Sample -> Chromatic Aberration -> Heat Distortion ->
// Linear Space -> Infernal Grade -> Contrast -> Saturation -> Tint ->
// Black Crush -> Highlight Roll-Off -> Dither -> Quantize -> Grain ->
// Vignette -> sRGB Output
// ============================================================================

// ============================================================================
// UNIFORMS
// ============================================================================

uniform float u_contrast : hint_range(0.0, 2.0, 0.01) = 1.12;
uniform float u_saturation : hint_range(0.0, 2.0, 0.01) = 1.05;
uniform float u_infernal_tint : hint_range(0.0, 1.0, 0.01) = 0.12;
uniform float u_black_crush : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float u_highlight_rolloff : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform float u_dither_strength : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float u_color_levels : hint_range(4.0, 64.0, 1.0) = 28.0;
uniform float u_grain_strength : hint_range(0.0, 1.0, 0.01) = 0.08;
uniform float u_chromatic_amount : hint_range(0.0, 2.0, 0.01) = 0.6;
uniform float u_heat_strength : hint_range(0.0, 4.0, 0.01) = 0.8;
uniform float u_heat_speed : hint_range(0.0, 8.0, 0.01) = 1.5;
uniform float u_heat_scale : hint_range(0.0, 32.0, 0.01) = 12.0;
uniform float u_vignette_strength : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform float u_vignette_radius : hint_range(0.0, 2.0, 0.01) = 1.35;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// ============================================================================
// UTILITY
// ============================================================================

vec3 srgb_to_linear(vec3 c) { return pow(c, vec3(2.2)); }
vec3 linear_to_srgb(vec3 c) { return pow(c, vec3(1.0 / 2.2)); }
vec3 clamp3(vec3 c) { return clamp(c, vec3(0.0), vec3(1.0)); }

// ============================================================================
// SAMPLING (Chromatic + Heat - happens BEFORE color grading)
// ============================================================================

// Sample screen with chromatic aberration (sub-pixel, edge-only)
vec3 sample_chromatic(sampler2D tex, vec2 uv, float amount) {
    if (amount < 0.01) return texture(tex, uv).rgb;

    vec2 centered = uv * 2.0 - 1.0;
    float edge = smoothstep(0.0, 1.0, length(centered));
    vec2 dir = normalize(centered + 0.0001);
    vec2 off = dir * amount * 0.001 * edge;

    return vec3(
        texture(tex, uv + off * 1.0).r,
        texture(tex, uv + off * 0.5).g,
        texture(tex, uv - off * 0.3).b
    );
}

// Heat mask: hot = bright warm colors (lava), cool = dark/neutral (pillars, weapon)
float heat_mask(vec3 c) {
    float warmth = c.r * 0.5 + c.g * 0.3 - c.b * 0.2;
    return smoothstep(0.15, 0.45, warmth * max(max(c.r, c.g), c.b));
}

// Rising heat distortion - vertical shimmer on hot pixels only
vec2 heat_offset(vec2 uv, vec3 color, float time, float strength, float speed, float scale) {
    float mask = heat_mask(color);
    if (mask < 0.01) return vec2(0.0);

    float t = time * speed;
    float w1 = sin(uv.y * scale + t);
    float w2 = sin(uv.y * scale * 1.7 + t * 1.3);
    float w3 = sin(uv.x * scale * 0.5 + t * 0.7);
    float d = (w1 * 0.5 + w2 * 0.3 + w3 * 0.2);

    return vec2((d) * 0.3, (d) * 0.9) * strength * 0.003 * mask;
}

// Combined screen sampling: chromatic + heat-distorted UVs
vec3 sample_screen(sampler2D tex, vec2 uv, float time, float chroma, float heat_str, float heat_spd, float heat_scl) {
    // First, get a base sample for heat mask (no chromatic yet)
    vec3 base = texture(tex, uv).rgb;

    // Apply heat distortion to UVs based on base sample
    vec2 distorted_uv = uv + heat_offset(uv, base, time, heat_str, heat_spd, heat_scl);

    // Sample with chromatic aberration at the distorted UV
    return sample_chromatic(tex, distorted_uv, chroma);
}

// ============================================================================
// COLOR PROCESSING (runs ONCE per pixel)
// ============================================================================

vec3 apply_infernal_grade(vec3 c) {
    c.r += c.r * 0.06 + c.g * 0.04;
    float shadow = 1.0 - max(max(c.r, c.g), c.b);
    c += vec3(0.08, 0.02, 0.0) * shadow;
    float hl = smoothstep(0.4, 0.9, max(max(c.r, c.g), c.b));
    c.b -= c.b * 0.08 * hl;
    return clamp3(c);
}

vec3 apply_contrast(vec3 c, float contrast) {
    return (c - 0.5) * contrast + 0.5;
}

vec3 apply_saturation(vec3 c, float sat) {
    return mix(vec3(dot(c, vec3(0.299, 0.587, 0.114))), c, sat);
}

vec3 apply_infernal_tint(vec3 c, float strength) {
    return mix(c, c * vec3(0.85, 0.25, 0.08), strength * 0.3);
}

vec3 apply_black_crush(vec3 c, float strength) {
    return c * (1.0 - strength * 0.5 * (1.0 - smoothstep(0.0, 0.15, length(c))));
}

vec3 apply_highlight_rolloff(vec3 c, float strength) {
    vec3 comp = c / (c + vec3(1.0 - strength));
    return mix(c, comp, smoothstep(0.5, 0.9, max(max(c.r, c.g), c.b)) * strength);
}

// ============================================================================
// DITHER & QUANTIZE
// ============================================================================

float bayer(ivec2 p) {
    // 4x4 Bayer matrix unrolled
    int v = 0;
    if (p.x == 0) {
        if (p.y == 0) v = 0; else if (p.y == 1) v = 8;
        else if (p.y == 2) v = 2; else v = 10;
    } else if (p.x == 1) {
        if (p.y == 0) v = 12; else if (p.y == 1) v = 4;
        else if (p.y == 2) v = 14; else v = 6;
    } else if (p.x == 2) {
        if (p.y == 0) v = 3; else if (p.y == 1) v = 11;
        else if (p.y == 2) v = 1; else v = 9;
    } else {
        if (p.y == 0) v = 15; else if (p.y == 1) v = 7;
        else if (p.y == 2) v = 13; else v = 5;
    }
    return float(v) / 16.0;
}

vec3 apply_dither(vec3 c, vec2 px, float strength, float levels) {
    float d = bayer(ivec2(px) % 4) - 0.5;
    return c + vec3(d * strength / levels);
}

vec3 apply_quantize(vec3 c, float levels) {
    return round(c * levels) / levels;
}

// ============================================================================
// GRAIN & VIGNETTE
// ============================================================================

float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec3 apply_grain(vec3 c, vec2 uv, float strength, float time) {
    float g = hash(uv * vec2(1280.0, 720.0) + time * 0.7) - 0.5;
    float lum = dot(c, vec3(0.299, 0.587, 0.114));
    return c + g * strength * (1.0 - smoothstep(0.3, 0.8, lum));
}

vec3 apply_vignette(vec3 c, vec2 uv, float strength, float radius) {
    float d = length(uv * 2.0 - 1.0);
    return c * (1.0 - smoothstep(radius * 0.5, radius, d) * strength);
}

// ============================================================================
// MAIN
// ============================================================================

void fragment() {
    // Step 1-2: Sample screen with chromatic aberration + heat distortion
    vec3 color = sample_screen(screen_texture, UV, TIME, 
                                u_chromatic_amount, u_heat_strength, 
                                u_heat_speed, u_heat_scale);

    // Step 3: Linear space
    color = srgb_to_linear(color);

    // Step 4-9: Color grading pipeline (ONE pass)
    color = apply_infernal_grade(color);
    color = apply_contrast(color, u_contrast);
    color = apply_saturation(color, u_saturation);
    color = apply_infernal_tint(color, u_infernal_tint);
    color = apply_black_crush(color, u_black_crush);
    color = apply_highlight_rolloff(color, u_highlight_rolloff);
    color = clamp3(color);

    // Step 10-11: Dither + Quantize
    color = apply_dither(color, FRAGCOORD.xy, u_dither_strength, u_color_levels);
    color = apply_quantize(color, u_color_levels);

    // Step 12: Film grain (in linear space)
    color = apply_grain(color, UV, u_grain_strength, TIME);

    // Step 13: Back to sRGB
    color = linear_to_srgb(color);

    // Step 14: Vignette (in sRGB for perceptual correctness)
    color = apply_vignette(color, UV, u_vignette_strength, u_vignette_radius);

    COLOR = vec4(color, 1.0);
}
