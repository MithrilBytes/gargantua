#include "Common.h"

// Additive point sprites. Each particle radiates (T / T_peak)^4 in its
// blackbody color; the sprite footprint is normalized so zooming conserves
// the light a particle contributes.

struct SpriteVertex {
    float4 position [[position]];
    float size [[point_size]];
    half3 color;
};

vertex SpriteVertex spriteVertex(uint vid [[vertex_id]],
                                 device const Particle* particles [[buffer(0)]],
                                 constant SpriteUniforms& u [[buffer(1)]],
                                 texture1d<half, access::sample> blackbody [[texture(0)]]) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    Particle p = particles[vid];
    float4 clip = u.viewProjection * float4(float3(p.position), 1.0f);
    float depth = max(clip.w, 0.1f);
    float size = clamp(2.0f * u.spriteRadius * u.pixelsPerUnit / depth, 1.0f, 48.0f);
    float relative = p.temperature / u.peakTemperature;
    float energy = relative * relative * relative * relative;
    half3 tint = blackbody.sample(linearClamp, blackbodyCoordinate(p.temperature)).rgb;

    SpriteVertex out;
    out.position = clip;
    out.size = size;
    out.color = tint * half(energy * u.exposure / (size * size));
    return out;
}

fragment half4 spriteFragment(SpriteVertex in [[stage_in]], float2 coord [[point_coord]]) {
    float2 d = (coord - 0.5f) * 2.0f;
    float r2 = dot(d, d);
    half falloff = half(exp(-4.0f * r2)) * half(r2 < 1.0f);
    return half4(in.color * falloff, 1.0h);
}
