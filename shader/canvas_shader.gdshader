shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform vec2 target_resolution = vec2(320.0, 240.0);

uniform float color_levels : hint_range(2.0, 8.0) = 4.0;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.4;

// brightness control
uniform float gamma_lift : hint_range(0.5, 2.0) = 0.9;
uniform float brightness_boost : hint_range(0.5, 2.0) = 1.1;

// Bayer 4x4 dither
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

// palette limiter: map any color to your “warm palette”
vec3 warm_palette(vec3 col) {
    float r = col.r;
    float g = col.g * 0.5; 
    float b = col.b * 0.2; 
    vec3 mapped = vec3(r, g, b);
    mapped = normalize(mapped) * length(mapped);
    return mapped;
}

// subtle procedural noise
float subtle_noise(vec2 uv) {
    return (fract(sin(dot(uv * 1000.0, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * 0.02;
}

void fragment() {
    // subtle pixelation
    vec2 pixel = floor(SCREEN_UV * target_resolution);
    vec2 block_uv = (floor(pixel / 1.05) * 1.05) / target_resolution;

    vec3 col = texture(screen_texture, block_uv).rgb;

    // apply palette
    col = warm_palette(col);

    // luminance
    float lum = dot(col, vec3(0.299, 0.587, 0.114));
    lum = pow(lum, gamma_lift) * brightness_boost;

    // add tiny noise
    lum += subtle_noise(SCREEN_UV);

    // darken the top slightly for sky depth
    lum *= mix(0.9, 1.0, SCREEN_UV.y);

    // soft Bayer dither
    float dither = bayer4(pixel) * dither_strength;
    float mask = smoothstep(0.05, 0.95, lum);
    lum += dither * mask;

    // quantization
    float stepped = floor(lum * (color_levels - 1.0) + 0.5) / (color_levels - 1.0);
    stepped = clamp(stepped, 0.0, 1.0);

    // preserve color ratios
    vec3 final = col * (stepped / max(lum, 0.001));
    final *= brightness_boost;

    // clamp palette
    final.r = clamp(final.r, 0.0, 1.0);
    final.g = clamp(final.g, 0.0, 0.5);
    final.b = clamp(final.b, 0.0, 0.3);

    COLOR = vec4(final, 1.0);
}