#include <metal_stdlib>
using namespace metal;

// 16-byte aligned per-line uniform (exact stride: 32 bytes)
struct SpectralLineUniform {
    float4 colorAndIntensity; // xyz = normalized RGB, w = relativeIntensity (0.0 - 1.0)
    float4 params;            // x = audioFrequencyHz, y = wavelengthNm, z = reserved, w = reserved
};

// 16-byte aligned plasma uniforms (exact stride: 64 + 8 * 32 = 320 bytes)
struct PlasmaUniforms {
    float4 timing;            // x = time (s), y = beatPhase (0..1), z = envelopeLevel (0..1), w = intensityScale
    uint4 meta;               // x = lineCount (0..8), y = activeLineIndex (0xFFFFFFFF = blend all), z = visualMode, w = reserved
    float4 aspectAndViewport; // x = aspectRatio (w/h), y = viewportWidth, z = viewportHeight, w = reserved
    float4 touchControl;      // x = touchU (0..1), y = touchV (0..1), z = touchStrength (0..1), w = pinchScale (0.5..2.5)
    SpectralLineUniform lines[8];
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Full-screen triangle vertex shader (3 vertices cover [-1, 1] with zero vertex buffer allocation)
vertex VertexOut plasmaVertexShader(uint vertexID [[vertex_id]]) {
    VertexOut out;
    float2 uv = float2((vertexID << 1) & 2, vertexID & 2);
    out.position = float4(uv * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(uv.x, 1.0 - uv.y);
    return out;
}

// Procedural hash & smooth value noise for gas-discharge filament turbulence
static inline float hash21(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
}

static inline float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i + float2(0.0, 0.0));
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 3-octave fractional Brownian motion for organic ionized gas plumes
static inline float plasmaFBM(float2 p) {
    float value = 0.0;
    float amp = 0.52;
    for (int i = 0; i < 3; i++) {
        value += amp * valueNoise(p);
        p = p * 2.07 + float2(13.7, 7.3);
        amp *= 0.5;
    }
    return value;
}

// Multi-spectral Geissler / Crookes gas-discharge plasma fragment shader with interactive touch vortices
fragment float4 plasmaFragmentShader(VertexOut in [[stage_in]],
                                     constant PlasmaUniforms &uniforms [[buffer(0)]]) {
    float2 uv = in.uv * 2.0 - 1.0;
    float aspect = max(uniforms.aspectAndViewport.x, 0.1);
    float2 centered = (aspect >= 1.0)
        ? float2(uv.x * aspect, uv.y)
        : float2(uv.x, uv.y / aspect);

    // Interactive touch vortex & pinch scaling
    float2 touchUV = uniforms.touchControl.xy * 2.0 - 1.0;
    float2 touchCenter = (aspect >= 1.0)
        ? float2(touchUV.x * aspect, touchUV.y)
        : float2(touchUV.x, touchUV.y / aspect);
    float touchStrength = clamp(uniforms.touchControl.z, 0.0, 1.0);
    float pinchScale = clamp(uniforms.touchControl.w, 0.5, 2.5);

    float2 toTouch = centered - touchCenter;
    float touchDist = length(toTouch);

    // Tangential electromagnetic vortex swirl under active fingertip
    float2 warped = centered;
    if (touchStrength > 0.001) {
        float swirl = touchStrength * 2.4 * pinchScale * exp(-touchDist * 2.5);
        float cs = cos(swirl);
        float sn = sin(swirl);
        float2 rotated = float2(
            toTouch.x * cs - toTouch.y * sn,
            toTouch.x * sn + toTouch.y * cs
        );
        warped = touchCenter + rotated;
    }

    float dist = length(warped) / pinchScale;
    float angle = atan2(warped.y, warped.x);

    float t = uniforms.timing.x;
    float beatPhase = uniforms.timing.y;
    float envelope = clamp(uniforms.timing.z, 0.0, 1.0);
    float intensityScale = max(uniforms.timing.w, 0.0);

    // Organic ionized plasma filament turbulence
    float n1 = plasmaFBM(float2(dist * 3.2 - t * 0.75, angle * 2.0 + t * 0.28));
    float n2 = valueNoise(warped * 4.5 + float2(t * 0.42, -t * 0.35));
    float turbulence = mix(n1, n2, 0.38);

    // Beat-driven radial expansion + envelope-coupled gas core & corona
    float pulse = 1.0 + 0.18 * sin(beatPhase * 2.0 * M_PI_F) + 0.22 * envelope;
    float core = exp(-dist * (2.9 / pulse)) * (0.72 + 0.55 * turbulence);
    float corona = exp(-dist * (1.25 / max(pulse * 0.9, 0.5))) * (0.28 + 0.25 * n1);
    float filamentArc = exp(-abs(dist - 0.42 * pulse) * 7.5) * (0.35 * turbulence);

    // Plasma tendril drawn directly toward fingertip (plasma-globe dielectric attraction)
    float touchTendril = exp(-touchDist * (3.8 / pinchScale)) * touchStrength * (0.75 + 0.45 * turbulence);

    uint count = min(uniforms.meta.x, 8u);
    uint activeLine = uniforms.meta.y; // 0xFFFFFFFF => blend all emission lines

    float3 totalColor = float3(0.0);

    for (uint i = 0; i < count; i++) {
        SpectralLineUniform line = uniforms.lines[i];
        float3 lineRGB = line.colorAndIntensity.xyz;
        float lineIntensity = line.colorAndIntensity.w;
        float freqHz = line.params.x;

        // Multi-line cycle mode emphasizes the currently active emission line with a subtle ambient bed
        float focusWeight = (activeLine == 0xFFFFFFFFu || activeLine == i) ? 1.0 : 0.14;

        // Multi-frequency standing-wave harmonic ripple derived from the audio pitch
        float rippleFreq = 12.0 + float(i) * 2.2;
        float harmonicRipple = sin(dist * rippleFreq - t * (freqHz * 0.0055) + angle * 2.0 + float(i));
        float lineWeight = lineIntensity * focusWeight * (
            core +
            corona * (0.55 + 0.45 * harmonicRipple) +
            filamentArc +
            touchTendril
        );

        totalColor += lineRGB * lineWeight;
    }

    // Modulate by beat envelope & user brightness scale
    float energyGain = (0.18 + 0.82 * envelope) * intensityScale;
    totalColor *= energyGain;

    // Subtle incandescent white-hot plasma center on peak beats & touch point
    float whiteCore = (exp(-dist * 7.0) * envelope + exp(-touchDist * 11.0) * touchStrength * 0.65) * intensityScale * 0.35;
    totalColor += float3(whiteCore);

    // Filmic exponential tone mapping to prevent hard clipping on rich chords (e.g. Neon, Iron)
    totalColor = 1.0 - exp(-totalColor * 1.45);

    return float4(clamp(totalColor, 0.0, 1.0), 1.0);
}
