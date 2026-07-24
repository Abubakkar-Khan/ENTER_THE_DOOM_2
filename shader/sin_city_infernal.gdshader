shader_type canvas_item;

// ============================================================================
// SIN CITY INFERNAL — CINEMATIC POST-PROCESS
// Godot 4.5 | Fullscreen ColorRect | Forward+
// ============================================================================
// Scene-aware post-process reducing the world to pure black, white, and
// selective crimson accents. Graphic novel brutality meets infernal horror FPS.
//
// Pipeline:
//   Screen → Heat Distort → Chromatic (edge-only) → Lava Glow →
//   Accent Mask → Monochrome Grade → Accent Remap → Shadow Warmth →
//   Selective Quantize → 8x8 Bayer Dither → Unsharp Mask →
//   Soft Vignette → sRGB Output
// ============================================================================

// ============================================================================
// UNIFORMS
// ============================================================================

uniform float u_contrast : hint_range(1.0, 3.0, 0.01) = 1.75;
uniform float u_shadow_crush : hint_range(0.0, 0.25, 0.01) = 0.09;
uniform float u_accent_blend : hint_range(0.0, 1.0, 0.01) = 0.95;
uniform float u_shadow_warmth : hint_range(0.0, 1.0, 0.01) = 0.25;

uniform float u_color_levels : hint_range(24.0, 32.0, 1.0) = 28.0;
uniform float u_dither_strength : hint_range(0.0, 1.0, 0.01) = 0.22;

uniform float u_heat_strength : hint_range(0.0, 2.0, 0.01) = 0.55;
uniform float u_heat_speed : hint_range(0.0, 3.0, 0.01) = 0.9;
uniform float u_heat_scale : hint_range(4.0, 24.0, 0.01) = 12.0;

uniform float u_glow_intensity : hint_range(0.0, 1.0, 0.01) = 0.20;
uniform float u_glow_radius : hint_range(1.0, 6.0, 0.01) = 2.0;

uniform float u_sharpen : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float u_chromatic : hint_range(0.0, 1.5, 0.01) = 0.40;
uniform float u_vignette_strength : hint_range(0.0, 1.0, 0.01) = 0.22;
uniform float u_vignette_radius : hint_range(0.5, 2.0, 0.01) = 1.45;

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

// Bright warm pixels = lava. 0 for cool/dark.
float lava_mask(vec3 c) {
    float warmth = c.r * 0.5 + c.g * 0.3 - c.b * 0.2;
    return smoothstep(0.2, 0.5, warmth * max(max(c.r, c.g), c.b));
}

// Detects blood, lava, eye, and key highlights by color signature.
// Conservative — only clearly warm/red/saturated pixels pass.
float accent_mask(vec3 c) {
    float max_c = max(max(c.r, c.g), c.b);
    float min_c = min(min(c.r, c.g), c.b);
    float sat = max_c > 0.001 ? (max_c - min_c) / max_c : 0.0;

    // Blood: deep saturated red, very low green/blue
    float blood = smoothstep(0.18, 0.60, c.r)
                * (1.0 - smoothstep(0.0, 0.15, c.g))
                * (1.0 - smoothstep(0.0, 0.15, c.b))
                * smoothstep(0.12, 0.6, sat);

    // Lava: bright warm orange-red
    float lava = smoothstep(0.48, 0.90, c.r)
               * smoothstep(0.06, 0.45, c.g)
               * (1.0 - smoothstep(0.0, 0.20, c.b))
               * smoothstep(0.40, 1.0, max_c);

    // Bright warm highlights (eye, key lights)
    float highlight = smoothstep(0.58, 1.0, max_c)
                    * smoothstep(0.0, 0.30, c.r - c.b)
                    * smoothstep(0.06, 0.45, sat);

    return clamp(blood + lava + highlight * 0.45, 0.0, 1.0);
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

// Tiny chromatic aberration, edge-only, sub-pixel. Branch is spatially coherent.
vec3 sample_chromatic(sampler2D tex, vec2 uv, float amount) {
    vec2 c = uv * 2.0 - 1.0;
    float edge = smoothstep(0.0, 1.0, length(c));
    if (edge < 0.01 || amount < 0.01) return texture(tex, uv).rgb;

    vec2 off = normalize(c + 0.0001) * amount * 0.001 * edge;
    return vec3(texture(tex, uv + off * 1.0).r,
                texture(tex, uv + off * 0.5).g,
                texture(tex, uv - off * 0.3).b);
}

// ============================================================================
// COLOR PROCESSING
// ============================================================================

// High-contrast monochrome with filmic curve and smooth shadow crush.
// Creates graphic novel blacks and clean whites.
vec3 monochrome_grade(vec3 c, float contrast, float crush) {
    float l = lum(c);
    // Filmic power curve
    l = pow(l, 0.82);
    // Contrast boost
    l = (l - 0.42) * contrast + 0.42;
    // Smooth shadow crush: smooth knee from black to visible
    float knee_low = crush * 0.6;
    float knee_high = crush * 2.5;
    l = l * smoothstep(knee_low, knee_high, l);
    return vec3(clamp(l, 0.0, 1.0));
}

// Remap accent pixels to the infernal crimson-red axis.
vec3 accent_remap(vec3 c) {
    float l = lum(c);
    float warmth = c.r * 0.5 + c.g * 0.15 - c.b * 0.12;
    float t = clamp(l + warmth * 0.22, 0.0, 1.0);

    // Linear-space accent stops
    vec3 deep = vec3(0.217, 0.000, 0.001);    // dark crimson
    vec3 blood = vec3(0.797, 0.001, 0.001);   // blood red
    vec3 scarlet = vec3(1.000, 0.014, 0.005); // bright scarlet

    if (t < 0.5) return mix(deep, blood, t * 2.0);
    return mix(blood, scarlet, (t - 0.5) * 2.0);
}

// Warmth in near-shadows only. Pure crushed blacks stay pure black.
vec3 shadow_warmth(vec3 c, float strength, float crush) {
    float l = lum(c);
    float mask = smoothstep(crush, crush * 3.5, l)
               * (1.0 - smoothstep(crush * 3.5, crush * 7.0, l));
    return c + vec3(0.035, 0.001, 0.002) * strength * mask;
}

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

    // --- Base sample for masks (original UVs, before distortion) ---
    vec3 base = texture(screen_texture, uv).rgb;
    float heat_mask = lava_mask(base);
    float accent = accent_mask(base);
    float detail = detail_mask(base);

    // --- Heat distortion offset (lava-only) ---
    vec2 heat = heat_offset(uv, heat_mask, TIME);

    // --- Sample center with chromatic aberration + heat ---
    vec3 c_c = sample_chromatic(screen_texture, uv + heat, u_chromatic);

    // --- Sample 4 neighbors (shared for glow + sharpen) ---
    vec2 g_off = sp * u_glow_radius;
    vec3 c_r = texture(screen_texture, uv + heat + vec2(g_off.x, 0.0)).rgb;
    vec3 c_l = texture(screen_texture, uv + heat + vec2(-g_off.x, 0.0)).rgb;
    vec3 c_u = texture(screen_texture, uv + heat + vec2(0.0, g_off.y)).rgb;
    vec3 c_d = texture(screen_texture, uv + heat + vec2(0.0, -g_off.y)).rgb;

    // --- Selective Lava Glow: warm bleed from bright neighbors ---
    float m_r = lava_mask(c_r);
    float m_l = lava_mask(c_l);
    float m_u = lava_mask(c_u);
    float m_d = lava_mask(c_d);
    float glow_w = m_r + m_l + m_u + m_d;
    vec3 glow = glow_w > 0.001
        ? (c_r * m_r + c_l * m_l + c_u * m_u + c_d * m_d) / glow_w
        : c_c;
    float glow_blend = glow_w * 0.25 * u_glow_intensity * (1.0 - lava_mask(c_c) * 0.5);
    vec3 color = mix(c_c, glow, glow_blend);

    // --- Convert to linear for color operations ---
    vec3 lin = srgb_to_linear(color);

    // --- Monochrome grade (non-accent pixels) ---
    vec3 mono = srgb_to_linear(monochrome_grade(color, u_contrast, u_shadow_crush));

    // --- Accent remap (accent pixels) ---
    vec3 accent_col = accent_remap(color);

    // --- Blend: monochrome world + crimson accents ---
    lin = mix(mono, accent_col, accent * u_accent_blend);

    // --- Subtle warmth in shadow knee (pure blacks stay black) ---
    lin = shadow_warmth(lin, u_shadow_warmth, u_shadow_crush);

    // --- Selective Quantization: flat faces heavy, edges light ---
    float levels = mix(u_color_levels, 48.0, detail);

    // --- 8x8 Bayer Dither ---
    lin += vec3((bayer8(ivec2(FRAGCOORD.xy)) - 0.5) * u_dither_strength / levels);
    lin = round(lin * levels) / levels;

    // --- Unsharp Mask using the same 4 neighbors ---
    // Neighbors must also go through the same grade for consistent sharpening
    vec3 n_r = mix(srgb_to_linear(monochrome_grade(c_r, u_contrast, u_shadow_crush)),
                   accent_remap(c_r), accent_mask(c_r) * u_accent_blend);
    vec3 n_l = mix(srgb_to_linear(monochrome_grade(c_l, u_contrast, u_shadow_crush)),
                   accent_remap(c_l), accent_mask(c_l) * u_accent_blend);
    vec3 n_u = mix(srgb_to_linear(monochrome_grade(c_u, u_contrast, u_shadow_crush)),
                   accent_remap(c_u), accent_mask(c_u) * u_accent_blend);
    vec3 n_d = mix(srgb_to_linear(monochrome_grade(c_d, u_contrast, u_shadow_crush)),
                   accent_remap(c_d), accent_mask(c_d) * u_accent_blend);
    vec3 blur = (n_r + n_l + n_u + n_d) * 0.25;
    lin = unsharp_mask(lin, blur, detail, u_sharpen);

    // --- Output ---
    vec3 out_color = linear_to_srgb(lin);
    out_color = apply_vignette(out_color, uv, u_vignette_strength, u_vignette_radius);
    COLOR = vec4(clamp3(out_color), 1.0);
}
