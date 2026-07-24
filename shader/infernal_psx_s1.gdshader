shader_type canvas_item;
render_mode unshaded;

//==================================================
// INFERNAL PSX POST PROCESS
// Part 1A
// Godot 4.5
//==================================================

uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;

//--------------------------------------------------
// COLOR
//--------------------------------------------------

uniform float contrast : hint_range(0.5,2.0) = 1.15;
uniform float saturation : hint_range(0.0,2.0) = 0.92;

uniform vec3 infernal_tint = vec3(
    1.08,
    1.02,
    0.96
);

//--------------------------------------------------
// RETRO
//--------------------------------------------------

uniform float color_levels : hint_range(8.0,64.0)=28.0;
uniform float dither_strength : hint_range(0.0,1.0)=0.35;

//--------------------------------------------------
// SCREEN FX
//--------------------------------------------------

uniform float chromatic_amount : hint_range(0.0,0.004)=0.0007;

uniform float grain_strength : hint_range(0.0,0.08)=0.015;

uniform float vignette_strength : hint_range(0.0,1.0)=0.18;
uniform float vignette_radius = 0.85;
uniform float vignette_softness = 0.35;

//--------------------------------------------------
// HEAT
//--------------------------------------------------

uniform float heat_strength = 0.003;
uniform float heat_scale = 40.0;
uniform float heat_speed = 1.3;
uniform float lava_threshold = 0.65;

//==================================================
// Utility
//==================================================

float luminance(vec3 c)
{
    return dot(
        c,
        vec3(
            0.2126,
            0.7152,
            0.0722
        )
    );
}

vec3 adjust_contrast(vec3 c,float k)
{
    return (c-0.5)*k+0.5;
}

vec3 adjust_saturation(vec3 c,float s)
{
    float l=luminance(c);

    return mix(
        vec3(l),
        c,
        s
    );
}

//==================================================
// Random
//==================================================

float random(vec2 p)
{
    return fract(
        sin(
            dot(
                p,
                vec2(127.1,311.7)
            )
        )*43758.5453123
    );
}

//==================================================
// Grain
//==================================================

float grain(vec2 uv)
{
    return random(
        uv*VIEWPORT_SIZE+
        TIME*35.0
    );
}

//==================================================
// Lava Mask
//==================================================

float lava_mask(vec3 c)
{
    float lum=luminance(c);

    float bright=smoothstep(
        lava_threshold,
        1.0,
        lum
    );

    float red=smoothstep(
        0.40,
        0.85,
        c.r-c.b
    );

    return bright*red;
}

//==================================================
// Heat Noise
//==================================================

float noise(vec2 p)
{
    return fract(
        sin(dot(
            p,
            vec2(
                41.0,
                289.0
            )
        ))*43758.5453
    );
}

vec2 heat_offset(vec2 uv)
{
    float n1=noise(
        uv*heat_scale+
        vec2(
            TIME*heat_speed,
            0.0
        )
    );

    float n2=noise(
        uv*heat_scale*0.7-
        vec2(
            0.0,
            TIME*heat_speed
        )
    );

    return vec2(
        n1-0.5,
        n2-0.5
    );
}

//==================================================
// Chromatic Aberration
//==================================================

vec3 sample_screen(vec2 uv)
{
    vec2 dir=normalize(
        uv-0.5
    );

    vec2 off=dir*chromatic_amount;

    float r=texture(
        screen_texture,
        uv+off
    ).r;

    float g=texture(
        screen_texture,
        uv
    ).g;

    float b=texture(
        screen_texture,
        uv-off
    ).b;

    return vec3(r,g,b);
}

//==================================================
// 8x8 BAYER DITHER
//==================================================

float bayer8(vec2 p)
{
    p = floor(mod(p, 8.0));

    int x = int(p.x);
    int y = int(p.y);

    const float m[64] = {
         0.0,32.0, 8.0,40.0, 2.0,34.0,10.0,42.0,
        48.0,16.0,56.0,24.0,50.0,18.0,58.0,26.0,
        12.0,44.0, 4.0,36.0,14.0,46.0, 6.0,38.0,
        60.0,28.0,52.0,20.0,62.0,30.0,54.0,22.0,
         3.0,35.0,11.0,43.0, 1.0,33.0, 9.0,41.0,
        51.0,19.0,59.0,27.0,49.0,17.0,57.0,25.0,
        15.0,47.0, 7.0,39.0,13.0,45.0, 5.0,37.0,
        63.0,31.0,55.0,23.0,61.0,29.0,53.0,21.0
    };

    return m[y * 8 + x] / 64.0;
}

//==================================================
// QUANTIZATION
//==================================================

vec3 quantize(vec3 col, vec2 uv)
{
    float dither =
        (bayer8(uv * VIEWPORT_SIZE) - 0.5)
        * dither_strength;

    col += dither / color_levels;

    col = floor(col * color_levels + 0.5)
        / color_levels;

    return clamp(col, 0.0, 1.0);
}

//==================================================
// VIGNETTE
//==================================================

float vignette(vec2 uv)
{
    vec2 p = uv * 2.0 - 1.0;

    float dist = length(p);

    float v = 1.0 - smoothstep(
        vignette_radius,
        vignette_radius + vignette_softness,
        dist
    );

    return mix(
        1.0,
        v,
        vignette_strength
    );
}

//==================================================
// SHADOW TINT
//==================================================

vec3 infernal_shadow(vec3 col)
{
    float l = luminance(col);

    float mask = smoothstep(
        0.55,
        0.0,
        l
    );

    vec3 tint = vec3(
        0.10,
        0.01,
        0.01
    );

    return mix(
        col,
        col + tint,
        mask
    );
}

//==================================================
// MAIN
//==================================================

void fragment()
{
    vec2 uv = SCREEN_UV;

    vec3 original = texture(
        screen_texture,
        uv
    ).rgb;

    float lava = lava_mask(original);

    uv += heat_offset(uv)
        * heat_strength
        * lava;

    vec3 col = sample_screen(uv);

    // Linear color
    col = pow(col, vec3(2.2));

    // Infernal grading
    col *= infernal_tint;
    col = adjust_contrast(col, contrast);
    col = adjust_saturation(col, saturation);
    col = infernal_shadow(col);

    // Back to sRGB
    col = pow(max(col, vec3(0.0)), vec3(1.0 / 2.2));

    // Retro quantization
    col = quantize(col, uv);

    // Film grain
    col += (grain(uv) - 0.5) * grain_strength;

    // Vignette
    col *= vignette(uv);

    COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}