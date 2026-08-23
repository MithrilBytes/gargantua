#include "Common.h"

// Present pass: tone map the linear HDR image into the drawable and lay the
// hud texture over it. Nothing here measures anything.

struct FullscreenVertex {
    float4 position [[position]];
    float2 uv;
};

vertex FullscreenVertex fullscreenVertex(uint vid [[vertex_id]]) {
    float2 positions[3] = { float2(-1.0f, -1.0f), float2(3.0f, -1.0f), float2(-1.0f, 3.0f) };
    FullscreenVertex out;
    out.position = float4(positions[vid], 0.0f, 1.0f);
    out.uv = float2(0.5f * (positions[vid].x + 1.0f), 0.5f * (1.0f - positions[vid].y));
    return out;
}

// Khronos PBR Neutral tone mapper, reference implementation.
// Khronos Group, 2024. PBR Neutral Tone Mapper Specification,
// github.com/KhronosGroup/ToneMapping, read 2026-08-22.
static float3 pbrNeutral(float3 color) {
    const float startCompression = 0.8f - 0.04f;
    const float desaturation = 0.15f;
    float x = min(color.r, min(color.g, color.b));
    float offset = x < 0.08f ? x - 6.25f * x * x : 0.04f;
    color -= offset;
    float peak = max(color.r, max(color.g, color.b));
    if (peak < startCompression) return color;
    const float d = 1.0f - startCompression;
    float newPeak = 1.0f - d * d / (peak + d - startCompression);
    color *= newPeak / peak;
    float g = 1.0f - 1.0f / (desaturation * (peak - newPeak) + 1.0f);
    return mix(color, float3(newPeak), g);
}

fragment half4 tonemapFragment(FullscreenVertex in [[stage_in]],
                               texture2d<float, access::sample> hdr [[texture(0)]],
                               constant PresentUniforms& u [[buffer(0)]]) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float3 color = hdr.sample(linearClamp, in.uv).rgb * u.exposure;
    return half4(half3(pbrNeutral(max(color, 0.0f))), 1.0h);
}

struct HudVertex {
    float4 position [[position]];
    float2 uv;
};

vertex HudVertex hudVertex(uint vid [[vertex_id]], constant PresentUniforms& u [[buffer(0)]]) {
    float2 corners[4] = { float2(0.0f, 0.0f), float2(1.0f, 0.0f), float2(0.0f, 1.0f), float2(1.0f, 1.0f) };
    float2 c = corners[vid];
    HudVertex out;
    out.position = float4(mix(u.hudRect.x, u.hudRect.z, c.x), mix(u.hudRect.y, u.hudRect.w, c.y), 0.0f, 1.0f);
    out.uv = float2(c.x, 1.0f - c.y);
    return out;
}

fragment half4 hudFragment(HudVertex in [[stage_in]], texture2d<half, access::sample> hud [[texture(0)]]) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    return hud.sample(linearClamp, in.uv);
}
