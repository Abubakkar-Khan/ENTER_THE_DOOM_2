shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D noise_tex : hint_default_black;
uniform float boil_speed = 0.3;   // Slow, thick boiling
uniform float scale = 2.0;        // Matches the granular density of your image
uniform float emission_strength = 1.00;

// --- Colors sampled exactly from your image ---
// Deepest dark spots (red-brown)
uniform vec3 sun_dark  = vec3(0.38, 0.08, 0.05);
// The main orange body
uniform vec3 sun_mid   = vec3(0.92, 0.45, 0.05);
// The bright yellow highlights
uniform vec3 sun_hot   = vec3(1.0, 0.88, 0.15);

void fragment() {
    // Boiling logic: two layers moving in small circles against each other
    float t = TIME * boil_speed;
    vec2 offset1 = vec2(cos(t), sin(t)) * 0.12;
    vec2 offset2 = vec2(sin(t * 0.8), cos(t * 0.8)) * 0.15;

    // Sample noise twice
    float n1 = texture(noise_tex, (UV * scale) + offset1).r;
    float n2 = texture(noise_tex, (UV * scale * 0.9) - offset2).r;

    // Combine for cellular "blob" growth
    float combined = (n1 + n2) * 0.5;

    // Sharpen the contrast to create the distinct granular look of the image
    // smoothstep(low, high, value)
    float mask = smoothstep(0.35, 0.75, combined);

    // Apply the sampled colors
    vec3 color = mix(sun_dark, sun_mid, mask);

    // Add the hot yellow spots (concentrated in the centers)
    float hot_mask = pow(mask, 3.5);
    color = mix(color, sun_hot, hot_mask);

    ALBEDO = color;
    EMISSION = color * emission_strength;
}