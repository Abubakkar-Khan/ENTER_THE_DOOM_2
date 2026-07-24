shader_type canvas_item;

// ============================================================================
// PURE INFERNAL MONOCHROME — CINEMATIC POST-PROCESS
// Godot 4.5 | Fullscreen ColorRect | Forward+
// ============================================================================
// Scene-aware, palette-driven post-process. Remaps the entire image through
// an artist-defined infernal color axis: Black → Dark Crimson → Crimson →
// Red → Orange → Yellow-White.
//
// Performance: 5 texture fetches total (1 center + 4 neighbors).
// Pipeline: Screen → Heat Distort → Chromatic → Glow → Linear →
//   Palette Map → Shadow Tint → Contrast → Selective Quantize →
//   8x8 Bayer Dither → Unsharp Mask → Vignette → sRGB
// ============================================================================

// ============================================================================
// UNIFORMS
// ============================================================================

uniform float u_palette_strength : hint_range(0.0, 1.0, 0.01) = 0.95;
uniform float u_contrast : hint_range(0.5, 2.0, 0.01) = 1.20;
uniform float u_saturation : hint_range(0.0, 2.0, 0.01) = 1.06;
uniform float u_shadow_tint : hint_range(0.0, 1.0, 0.01) = 0.42;

uniform float u_color_levels : hint_range(24.0, 32.0, 1.0) = 28.0;
uniform float u_dither_strength : hint_range(0.0, 1.0, 0.01) = 0.28;

uniform float u_heat_strength : hint_range(0.0, 2.0, 0.01) = 0.65;
uniform float u_heat_speed : hint_range(0.0, 3.0, 0.01) = 1.0;
uniform float u_heat_scale : hint_range(4.0, 24.0, 0.01) = 12.0;

uniform float u_glow_intensity : hint_range(0.0, 1.5, 0.01) = 0.32;
uniform float u_glow_radius : hint_range(1.0, 6.0, 0.01) = 2.0;

uniform float u_sharpen : hint_range(0.0, 1.0, 0.01) = 0.20;
uniform float u_chromatic : hint_range(0.0, 1.5, 0.01) = 0.45;
uniform float u_vignette_strength : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float u_vignette_radius : hint_range(0.5, 2.0, 0.01) = 1.4;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// ============================================================================
// UTILITY
// ============================================================================

vec3 srgb_to_linear(vec3 c) { return pow(c, vec3(2.2)); }
vec3 linear_to_srgb(vec3 c) { return pow(c, vec3(1.0 / 2.2)); }
vec3 clamp3(vec3 c) { return clamp(c, vec3(0.0), vec3(1.0)); }
float lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

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
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    mat2 rot = mat2(vec2(0.5, 0.5), vec2(-0.5, 0.5));
    for (int i = 0; i < 4; i++) {
        v += a * noise(p);
        p = rot * p * 2.0 + vec2(100.0);
        a *= 0.5;
    }
    return v;
}

// ============================================================================
// 8x8 BAYER ORDERED DITHER
// ============================================================================
// Exact 8x8 Bayer via recursive M_2 construction: M_8[i][j] = 4*M_4[i%4][j%4]
// + M_2[i/4][j/4]. Encoded with bit-interleaved M_2 lookups.

float bayer8(ivec2 p) {
    ivec2 c = p % 8;
    int v = 0;
    for (int i = 0; i < 3; i++) {
        int b = (((c.x >> i) & 1) << 1) | ((c.y >> i) & 1);
        v = (v << 2) | (b == 0 ? 0 : b == 1 ? 2 : b == 2 ? 3 : 1);
    }
    return float(v) / 64.0;
}

// ============================================================================
// MASKS
// ============================================================================

// Bright warm pixels = lava. Cool/dark = 0.
float lava_mask(vec3 c) {
    float warmth = c.r * 0.5 + c.g * 0.3 - c.b * 0.2;
    return smoothstep(0.2, 0.5, warmth * max(max(c.r, c.g), c.b));
}

// High fwidth = edges (weapon, enemies). Low = flat faces (terrain, pillars).
float detail_mask(vec3 c) {
    return smoothstep(0.0, 0.06, length(fwidth(c)));
}

// ============================================================================
// SAMPLING
// ============================================================================

// Rising hot air via FBM. Only lava pixels distort. Pillars/weapon stable.
vec2 heat_offset(vec2 uv, float mask, float time) {
    if (mask < 0.01) return vec2(0.0);
    vec2 fuv = uv * u_heat_scale + vec2(0.0, time * u_heat_speed);
    float d = fbm(fuv) * 0.5 + fbm(fuv + vec2(5.2, 1.3)) * 0.3
            + fbm(fuv * 0.5 + vec2(1.7, 8.3)) * 0.2;
    return vec2((d - 0.5) * 0.25, (d - 0.5) * 0.85) * u_heat_strength * mask * 0.004;
}

// Tiny chromatic aberration, edge-only, sub-pixel.
vec3 sample_chromatic(sampler2D tex, vec2 uv, float amount) {
    if (amount < 0.01) return texture(tex, uv).rgb;
    vec2 c = uv * 2.0 - 1.0;
    float edge = smoothstep(0.0, 1.0, length(c));
    vec2 off = normalize(c + 0.0001) * amount * 0.001 * edge;
    return vec3(texture(tex, uv + off * 1.0).r,
                texture(tex, uv + off * 0.5).g,
                texture(tex, uv - off * 0.3).b);
}

// ============================================================================
// INFERNAL PALETTE
// ============================================================================
// 6-stop artist-defined axis. Intensity weights luminance toward warm colors
// so lava maps high and cool shadows map low.

float infernal_intensity(vec3 c) {
    return clamp(lum(c) + c.r * 0.25 + c.g * 0.08 - c.b * 0.18, 0.0, 1.0);
}

vec3 infernal_palette(float t) {
    vec3 s0 = vec3(0.0, 0.0, 0.0);
    vec3 s1 = vec3(0.08, 0.0, 0.015);
    vec3 s2 = vec3(0.38, 0.015, 0.025);
    vec3 s3 = vec3(0.78, 0.04, 0.02);
    vec3 s4 = vec3(0.96, 0.42, 0.06);
    vec3 s5 = vec3(1.0, 0.88, 0.32);
    vec3 s6 = vec3(1.0, 0.96, 0.82);

    float p = t * 6.0;
    int i = int(floor(p));
    float f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    if (i <= 0) return mix(s0, s1, f);
    if (i == 1) return mix(s1, s2, f);
    if (i == 2) return mix(s2, s3, f);
    if (i == 3) return mix(s3, s4, f);
    if (i == 4) return mix(s4, s5, f);
    return mix(s5, s6, f);
}

// ============================================================================
// COLOR PROCESSING
// ============================================================================

vec3 shadow_tint(vec3 c, float strength) {
    return c + vec3(0.06, 0.003, 0.008) * (1.0 - smoothstep(0.0, 0.20, lum(c))) * strength;
}

vec3 apply_contrast(vec3 c, float contrast) { return (c - 0.5) * contrast + 0.5; }
vec3 apply_saturation(vec3 c, float sat) { return mix(vec3(lum(c)), c, sat); }

// Unsharp mask: recover crisp edges after quantization. Masked by detail.
vec3 unsharp_mask(vec3 center, vec3 blur, float detail, float strength) {
    return mix(center, center + (center - blur) * strength, strength * detail);
}

// ============================================================================
// VIGNETTE
// ============================================================================

vec3 apply_vignette(vec3 c, vec2 uv, float strength, float radius) {
    return c * (1.0 - smoothstep(radius * 0.5, radius, length(uv * 2.0 - 1.0)) * strength);
}

// ============================================================================
// MAIN
// ============================================================================

void fragment() {
    vec2 uv = UV;
    vec2 sp = SCREEN_PIXEL_SIZE;

    // --- Compute heat offset once (lava-only) ---
    vec3 base = texture(screen_texture, uv).rgb;
    float heat_mask = lava_mask(base);
    vec2 heat = heat_offset(uv, heat_mask, TIME);

    // --- Sample center + 4 neighbors (5 fetches total) ---
    // Center gets chromatic aberration; neighbors are simple samples.
    vec3 c_c = sample_chromatic(screen_texture, uv + heat, u_chromatic);
    vec3 c_r = texture(screen_texture, uv + heat + vec2(sp.x * u_glow_radius, 0.0)).rgb;
    vec3 c_l = texture(screen_texture, uv + heat + vec2(-sp.x * u_glow_radius, 0.0)).rgb;
    vec3 c_u = texture(screen_texture, uv + heat + vec2(0.0, sp.y * u_glow_radius)).rgb;
    vec3 c_d = texture(screen_texture, uv + heat + vec2(0.0, -sp.y * u_glow_radius)).rgb;

    // --- Lava Glow: warm bleed from bright neighbors into dark pixels ---
    float m_r = lava_mask(c_r);
    float m_l = lava_mask(c_l);
    float m_u = lava_mask(c_u);
    float m_d = lava_mask(c_d);
    float glow_w = m_r + m_l + m_u + m_d;
    vec3 glow = glow_w > 0.001 ? (c_r * m_r + c_l * m_l + c_u * m_u + c_d * m_d) / glow_w : c_c;
    float glow_blend = glow_w * 0.25 * u_glow_intensity * (1.0 - lava_mask(c_c) * 0.5);
    vec3 color = mix(c_c, glow, glow_blend);

    // --- Convert to linear and apply infernal palette ---
    vec3 lin = srgb_to_linear(color);
    float intensity = infernal_intensity(color);
    vec3 mapped = srgb_to_linear(infernal_palette(intensity));
    lin = mix(lin, mapped, u_palette_strength);

    // --- Color pipeline (single pass) ---
    lin = shadow_tint(lin, u_shadow_tint);
    lin = apply_contrast(lin, u_contrast);
    lin = apply_saturation(lin, u_saturation);
    lin = clamp3(lin);

    // --- Selective Quantization: flat faces heavy, edges light ---
    float detail = detail_mask(base);
    float levels = mix(u_color_levels, 32.0, detail);

    // --- 8x8 Bayer Dither ---
    lin += vec3((bayer8(ivec2(FRAGCOORD.xy)) - 0.5) * u_dither_strength / levels);
    lin = round(lin * levels) / levels;

    // --- Unsharp Mask using the same 4 neighbors (palette-mapped) ---
    vec3 lin_r = srgb_to_linear(mix(c_r, infernal_palette(infernal_intensity(c_r)), u_palette_strength));
    vec3 lin_l = srgb_to_linear(mix(c_l, infernal_palette(infernal_intensity(c_l)), u_palette_strength));
    vec3 lin_u = srgb_to_linear(mix(c_u, infernal_palette(infernal_intensity(c_u)), u_palette_strength));
    vec3 lin_d = srgb_to_linear(mix(c_d, infernal_palette(infernal_intensity(c_d)), u_palette_strength));
    vec3 blur = (lin_r + lin_l + lin_u + lin_d) * 0.25;
    lin = unsharp_mask(lin, blur, detail, u_sharpen);

    // --- Output ---
    vec3 out_color = linear_to_srgb(lin);
    out_color = apply_vignette(out_color, uv, u_vignette_strength, u_vignette_radius);
    COLOR = vec4(clamp3(out_color), 1.0);
}
