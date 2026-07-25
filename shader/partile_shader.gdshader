shader_type canvas_item;
render_mode blend_add;

uniform float intensity = 3.0;
uniform float softness = 2.0;

void fragment() {
    vec2 uv = UV - vec2(0.5);
    float dist = length(uv) * 2.0;

    float falloff = clamp(1.0 - dist, 0.0, 1.0);
    float alpha = pow(falloff, softness);

    // Fire gradient
    vec3 outer = vec3(0.6, 0.05, 0.0);   // deep red
    vec3 mid   = vec3(1.0, 0.3, 0.0);    // orange
    vec3 core  = vec3(0.6, 0.05, 0.0);   // hot yellow/white

    vec3 color = mix(outer, mid, falloff);
    color = mix(color, core, pow(falloff, 3.0));

    color *= intensity * alpha;

    COLOR = vec4(color, alpha);
}
