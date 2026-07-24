shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform vec2 target_resolution = vec2(320.0, 240.0);

// brightness & warmth
uniform float gamma_lift : hint_range(0.5, 2.0) = 1.0;
uniform float brightness_boost : hint_range(0.5, 2.0) = 1.05;
uniform float warmth : hint_range(0.0, 0.2) = 0.015;

// subtle dark dither bits
uniform float dither_strength : hint_range(0.0, 0.15) = 0.08;
uniform float dither_scale : hint_range(50.0, 400.0) = 300.0;

// warm palette
vec3 warm_palette(vec3 col) {
    float r = col.r;
    float g = col.g * 0.55;
    float b = col.b * 0.25;
    return normalize(vec3(r, g, b)) * length(col);
}

// procedural dark bits for shadows
float shadow_bits(vec2 uv) {
    vec2 p = uv * dither_scale;
    vec2 id = floor(p);
    vec2 gv = fract(p);
    float rnd = fract(sin(dot(id, vec2(127.1, 311.7))) * 43758.5453);
    return step(gv.x + gv.y, 0.5 + rnd);
}

void fragment() {
    vec3 col = texture(screen_texture, SCREEN_UV).rgb;

    // apply warm palette
    col = warm_palette(col);

    // smooth luminance
    float lum = dot(col, vec3(0.299, 0.587, 0.114));
    lum = pow(lum, gamma_lift) * brightness_boost;

    // **fine blackish dither in shadows**
    float shadow_mask = 1.0 - smoothstep(0.35, 0.7, lum); // darker areas stronger
    float bits = shadow_bits(SCREEN_UV);
    col = mix(col, vec3(0.0), bits * shadow_mask * dither_strength);

    // subtle warmth in highlights
    col.r += warmth * (1.0 - lum) * 0.5;
    col.g += warmth * 0.25 * (1.0 - lum) * 0.5;

    COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}