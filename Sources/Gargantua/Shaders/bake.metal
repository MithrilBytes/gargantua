#include "Geodesic.h"

// The bake strategy. For a stationary camera the geodesics do not change,
// so each ray's sample points inside the disk slab are integrated once and
// stored; every frame after that is a walk over stored positions. Samples
// are spaced at least `bakeSpacing` apart along the path so the small steps
// near the hole do not spend the budget on a single voxel.

static inline uint packHalf2(float a, float b) {
    return as_type<uint>(half2(half(a), half(b)));
}

static inline half2 unpackHalf2(uint packed) {
    return as_type<half2>(packed);
}

kernel void bakeRays(device half4* samples [[buffer(0)]],
                     device BakedRay* headers [[buffer(1)]],
                     constant MarchUniforms& u [[buffer(2)]],
                     device atomic_uint* overflow [[buffer(3)]],
                     texture1d<float, access::sample> sphereSweep [[texture(7)]],
                     texture1d<float, access::sample> cameraSweep [[texture(8)]],
                     texture1d<float, access::sample> skySweep [[texture(9)]],
                     uint2 gid [[thread_position_in_grid]]) {
    uint2 pixel = u.tileOrigin + gid;
    if (any(pixel >= u.resolution)) return;
    uint index = pixel.y * u.resolution.x + pixel.x;
    device half4* slot = samples + index * u.bakeCapacity;

    float2 sample = float2(pixel) + 0.5f;
    float2 ndc = float2((2.0f * sample.x / float(u.resolution.x) - 1.0f) * u.tanHalfFov.x,
                        (1.0f - 2.0f * sample.y / float(u.resolution.y)) * u.tanHalfFov.y);
    float3 direction = normalize(u.cameraForward + ndc.x * u.cameraRight + ndc.y * u.cameraUp);
    PreparedRay prepared = prepareRay(u.cameraPosition, direction, u, sphereSweep, cameraSweep, skySweep);
    if (prepared.skyOnly) {
        BakedRay header;
        header.count = 0u;
        header.fallsIn = 0u;
        header.directionXY = packHalf2(prepared.sky.x, prepared.sky.y);
        header.directionZDepth = packHalf2(prepared.sky.z, 1.0f);
        headers[index] = header;
        return;
    }
    PlaneRay ray = prepared.ray;

    float3 previous = rayPosition(ray);
    float sinceSample = 0.0f;
    float travelled = 0.0f;
    float firstSampleDepth = -1.0f;
    uint count = 0u;
    bool overflowed = false;
    uint outcome = RayExhausted;
    bool leftSphere = false;
    for (uint k = 0u; k < STEP_CAP_STILL; ++k) {
        if (k >= u.geodesic.stepCap) break;
        float h = rayStepLength(previous, ray.s.r, u.geodesic);
        RayState before = ray.s;
        ray.s = rayStep(ray.s, h);
        if (u.sphereRadius > 0.0f && ray.s.r >= u.sphereRadius && ray.s.rDot > 0.0f && before.r < u.sphereRadius) {
            ray.s = rayStep(before, h * (u.sphereRadius - before.r) / (ray.s.r - before.r));
        }
        float3 position = rayPosition(ray);
        float pathLength = length(position - previous);
        sinceSample += pathLength;
        travelled += pathLength;
        previous = position;
        if (ray.s.r <= u.geodesic.captureRadius) { outcome = RayCaptured; break; }
        if (abs(position.z) < DISK_SLAB_HALF_HEIGHT && all(abs(position.xy) < u.volumeHalfExtent) && sinceSample >= u.bakeSpacing) {
            if (count < u.bakeCapacity) {
                slot[count] = half4(half3(position), half(sinceSample));
                count += 1u;
                if (firstSampleDepth < 0.0f) firstSampleDepth = travelled;
            } else {
                overflowed = true;
            }
            sinceSample = 0.0f;
        }
        if (u.sphereRadius > 0.0f && ray.s.r >= u.sphereRadius && ray.s.rDot > 0.0f) { outcome = RayEscaped; leftSphere = true; break; }
        if (ray.s.r >= u.geodesic.escapeRadius) { outcome = RayEscaped; break; }
    }
    bool fallsIn = outcome == RayCaptured ||
        (outcome == RayExhausted && ray.s.rDot < 0.0f && abs(ray.angularMomentum) < B_CRITICAL * ray.energy);
    float3 final = leftSphere ? sphereExitDirection(ray, u, sphereSweep) : rayDirection(ray);
    float depth = firstSampleDepth >= 0.0f ? firstSampleDepth : travelled;
    BakedRay header;
    header.count = count;
    header.fallsIn = fallsIn ? 1u : 0u;
    header.directionXY = packHalf2(final.x, final.y);
    header.directionZDepth = packHalf2(final.z, min(depth / (2.0f * R_ESCAPE), 1.0f));
    headers[index] = header;
    if (overflowed) atomic_fetch_add_explicit(overflow, 1u, memory_order_relaxed);
}

kernel void walkRays(texture2d<half, access::write> output [[texture(0)]],
                     texture3d<half, access::sample> emission [[texture(2)]],
                     texture3d<half, access::sample> velocity [[texture(3)]],
                     texture1d<half, access::sample> blackbody [[texture(4)]],
                     texture2d<float, access::write> depthOut [[texture(5)]],
                     texture2d<half, access::write> motionOut [[texture(6)]],
                     device const half4* samples [[buffer(0)]],
                     device const BakedRay* headers [[buffer(1)]],
                     constant MarchUniforms& u [[buffer(2)]],
                     uint2 pixel [[thread_position_in_grid]]) {
    if (any(pixel >= u.resolution)) return;
    constexpr sampler trilinear(filter::linear, address::clamp_to_zero, coord::normalized);
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    uint index = pixel.y * u.resolution.x + pixel.x;
    BakedRay header = headers[index];
    device const half4* slot = samples + index * u.bakeCapacity;

    float3 color = float3(0.0f);
    float transmittance = 1.0f;
    float3 previous = u.cameraPosition;
    float3 weightedVelocity = float3(0.0f);
    float weightSum = 0.0f;
    for (uint k = 0u; k < BAKE_SAMPLES; ++k) {
        if (k >= header.count || k >= u.bakeCapacity || transmittance <= 0.004f) break;
        half4 stored = slot[k];
        float3 position = float3(stored.xyz);
        float pathLength = float(stored.w);
        float3 uvw = (position + u.volumeHalfExtent) / (2.0f * u.volumeHalfExtent);
        half4 e = emission.sample(trilinear, uvw);
        if (e.a > 0.0h) {
            float3 direction = normalize(position - previous);
            float3 gas = float3(velocity.sample(trilinear, uvw).xyz);
            float g3 = 1.0f;
            if (u.redshift != 0u) {
                float g = redshiftFactor(schwarzschildF(length(position)), direction, gas);
                g3 = g * g * g;
            }
            float alpha = 1.0f - exp(-u.opacityScale * float(e.a) * pathLength);
            float3 contribution = transmittance * float3(e.rgb) * g3 * pathLength;
            color += contribution;
            float weight = dot(contribution, float3(0.2126f, 0.7152f, 0.0722f));
            weightedVelocity += weight * gas;
            weightSum += weight;
            transmittance *= 1.0f - alpha;
        }
        previous = position;
    }
    if (header.fallsIn == 0u) {
        half2 xy = unpackHalf2(header.directionXY);
        half2 zd = unpackHalf2(header.directionZDepth);
        float3 direction = normalize(float3(float(xy.x), float(xy.y), float(zd.x)));
        color += transmittance * u.starBrightness * starfield(direction, u.starSeed, blackbody);
    }
    output.write(half4(half3(color), 1.0h), pixel);
    float normalizedDepth = float(unpackHalf2(header.directionZDepth).y);
    depthOut.write(float4(normalizedDepth, 0.0f, 0.0f, 0.0f), pixel);
    // The camera is static while walking, so the only motion is the gas's own.
    float2 sample = float2(pixel) + 0.5f;
    float2 ndc = float2((2.0f * sample.x / float(u.resolution.x) - 1.0f) * u.tanHalfFov.x,
                        (1.0f - 2.0f * sample.y / float(u.resolution.y)) * u.tanHalfFov.y);
    float3 direction = normalize(u.cameraForward + ndc.x * u.cameraRight + ndc.y * u.cameraUp);
    float3 gasVelocity = weightSum > 0.0f ? weightedVelocity / weightSum : float3(0.0f);
    float3 point = u.cameraPosition + direction * (normalizedDepth * 2.0f * R_ESCAPE);
    float3 gasDisplacement = gasVelocity * (SIM_DT * float(SIM_SUBSTEPS));
    float2 motion = previousPixel(point - gasDisplacement, u) - sample;
    motionOut.write(half4(half2(motion), 0.0h, 0.0h), pixel);
}
