#include "Geodesic.h"

// Pass 3. One thread per ray. Each ray is a null geodesic integrated from
// the eye; inside the volume cube it gathers emission with front to back
// compositing and leaves early once opaque. Escaped rays shade the
// starfield by their final direction; captured rays are black.

struct Sample {
    float3 emission;
    float density;
    float3 velocity;
};

static inline Sample sampleVolume(float3 position, float halfExtent,
                                  texture3d<half, access::sample> emission,
                                  texture3d<half, access::sample> velocity) {
    constexpr sampler trilinear(filter::linear, address::clamp_to_zero, coord::normalized);
    float3 uvw = (position + halfExtent) / (2.0f * halfExtent);
    half4 e = emission.sample(trilinear, uvw);
    half4 v = velocity.sample(trilinear, uvw);
    Sample s;
    s.emission = float3(e.rgb);
    s.density = float(e.a);
    s.velocity = float3(v.xyz);
    return s;
}

struct MarchResult {
    float3 color;
    float transmittance;
    float drift;
    uint steps;
    uint outcome;
    /// True when the ray ended by leaving the integration sphere outward.
    bool leftSphere;
    /// Opacity weighted distance along the ray to the gas it saw, or the
    /// distance travelled when it saw none.
    float depth;
};

// Whether a ray that ended falls into the hole: captured, or out of steps
// while moving inward with impact parameter below 3 sqrt(3).
static inline bool rayFallsIn(PlaneRay ray, uint outcome) {
    return outcome == RayCaptured ||
        (outcome == RayExhausted && ray.s.rDot < 0.0f && abs(ray.angularMomentum) < B_CRITICAL * ray.energy);
}

// The shared integration loop. `gather` is false for the validation probes,
// which only care about the geodesic.
static MarchResult marchRay(PlaneRay launched, constant MarchUniforms& u, bool gather,
                            texture3d<half, access::sample> emission,
                            texture3d<half, access::sample> velocity,
                            thread PlaneRay& rayOut) {
    PlaneRay ray = launched;
    float3 color = float3(0.0f);
    float transmittance = 1.0f;
    float3 previous = rayPosition(ray);
    uint outcome = RayExhausted;
    bool leftSphere = false;
    uint steps = 0u;
    float travelled = 0.0f;
    float weightedDepth = 0.0f;
    float depthWeight = 0.0f;
    for (uint k = 0u; k < STEP_CAP_STILL; ++k) {
        if (k >= u.geodesic.stepCap) break;
        float h = rayStepLength(previous, ray.s.r, u.geodesic);
        RayState before = ray.s;
        ray.s = rayStep(ray.s, h);
        steps = k + 1u;
        if (u.sphereRadius > 0.0f && ray.s.r >= u.sphereRadius && ray.s.rDot > 0.0f && before.r < u.sphereRadius) {
            // Land on the sphere rather than past it: the sweep table is
            // exact only from the sphere, and b / r^2 per unit of overshoot
            // would otherwise turn half a step into a visible sky shift.
            ray.s = rayStep(before, h * (u.sphereRadius - before.r) / (ray.s.r - before.r));
        }
        float3 position = rayPosition(ray);
        float pathLength = length(position - previous);
        travelled += pathLength;
        if (ray.s.r <= u.geodesic.captureRadius) { outcome = RayCaptured; break; }
        if (gather && abs(position.z) < DISK_SLAB_HALF_HEIGHT && all(abs(position.xy) < u.volumeHalfExtent) && transmittance > 0.004f) {
            Sample s = sampleVolume(position, u.volumeHalfExtent, emission, velocity);
            if (s.density > 0.0f) {
                float g3 = 1.0f;
                if (u.redshift != 0u) {
                    float g = redshiftFactor(schwarzschildF(ray.s.r), rayDirection(ray), s.velocity);
                    g3 = g * g * g;
                }
                float alpha = 1.0f - exp(-u.opacityScale * s.density * pathLength);
                float3 contribution = transmittance * s.emission * g3 * pathLength;
                color += contribution;
                float weight = dot(contribution, float3(0.2126f, 0.7152f, 0.0722f));
                weightedDepth += weight * travelled;
                depthWeight += weight;
                transmittance *= 1.0f - alpha;
            }
        }
        previous = position;
        if (u.sphereRadius > 0.0f && ray.s.r >= u.sphereRadius && ray.s.rDot > 0.0f) { outcome = RayEscaped; leftSphere = true; break; }
        if (ray.s.r >= u.geodesic.escapeRadius) { outcome = RayEscaped; break; }
    }
    rayOut = ray;
    MarchResult result;
    result.color = color;
    result.transmittance = transmittance;
    result.drift = rayDrift(ray);
    result.steps = steps;
    result.outcome = outcome;
    result.leftSphere = leftSphere;
    result.depth = depthWeight > 0.0f ? weightedDepth / depthWeight : travelled;
    return result;
}

// Sky direction for a ray that ended: the exact asymptote when it left the
// sphere, otherwise its last direction, the least wrong thing to draw for
// rays that ran out of steps or reached the escape radius.
static inline float3 skyDirection(PlaneRay ray, MarchResult m, constant MarchUniforms& u,
                                  texture1d<float, access::sample> sphereSweep) {
    return m.leftSphere ? sphereExitDirection(ray, u, sphereSweep) : rayDirection(ray);
}

// Pixel position of a world point in the previous frame's camera, for the
// temporal upscaler. Straight line reprojection; the lensing makes it an
// approximation, which shows as ghosting during fast camera moves.
static float2 previousPixel(float3 point, constant MarchUniforms& u) {
    float3 d = point - u.previousPosition;
    float z = max(dot(d, u.previousForward), 1e-3f);
    float sx = dot(d, u.previousRight) / z / u.tanHalfFov.x;
    float sy = dot(d, u.previousUp) / z / u.tanHalfFov.y;
    return float2(0.5f * (sx + 1.0f) * float(u.resolution.x), 0.5f * (1.0f - sy) * float(u.resolution.y));
}

kernel void marchImage(texture2d<half, access::write> output [[texture(0)]],
                       texture2d<half, access::write> debug [[texture(1)]],
                       texture3d<half, access::sample> emission [[texture(2)]],
                       texture3d<half, access::sample> velocity [[texture(3)]],
                       texture1d<half, access::sample> blackbody [[texture(4)]],
                       texture2d<float, access::write> depthOut [[texture(5)]],
                       texture2d<half, access::write> motionOut [[texture(6)]],
                       texture1d<float, access::sample> sphereSweep [[texture(7)]],
                       texture1d<float, access::sample> cameraSweep [[texture(8)]],
                       texture1d<float, access::sample> skySweep [[texture(9)]],
                       constant MarchUniforms& u [[buffer(0)]],
                       device atomic_uint* counters [[buffer(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
    uint2 pixel = u.tileOrigin + gid;
    bool active = all(pixel < u.resolution);
    uint2 local = gid;
    float3 color = float3(0.0f);
    float drift = 0.0f;
    uint steps = 0u;
    uint outcome = RayEscaped;
    if (active) {
        float2 sample = float2(pixel) + 0.5f + u.jitter;
        float2 ndc = float2((2.0f * sample.x / float(u.resolution.x) - 1.0f) * u.tanHalfFov.x,
                            (1.0f - 2.0f * sample.y / float(u.resolution.y)) * u.tanHalfFov.y);
        float3 direction = normalize(u.cameraForward + ndc.x * u.cameraRight + ndc.y * u.cameraUp);
        PreparedRay prepared = prepareRay(u.cameraPosition, direction, u, sphereSweep, cameraSweep, skySweep);
        float depth = 2.0f * R_ESCAPE;
        if (prepared.skyOnly) {
            color = u.starBrightness * starfield(prepared.sky, u.starSeed, blackbody);
        } else {
            PlaneRay ray;
            MarchResult m = marchRay(prepared.ray, u, true, emission, velocity, ray);
            color = m.color;
            drift = m.drift;
            steps = m.steps;
            outcome = m.outcome;
            depth = m.depth;
            if (!rayFallsIn(ray, outcome)) {
                color += m.transmittance * u.starBrightness * starfield(skyDirection(ray, m, u, sphereSweep), u.starSeed, blackbody);
            }
        }
        output.write(half4(half3(color), 1.0h), local);
        debug.write(half4(half(drift), half(float(steps)), half(float(outcome)), 1.0h), local);
        float3 point = u.cameraPosition + direction * depth;
        float2 motion = previousPixel(point, u) - (float2(pixel) + 0.5f);
        depthOut.write(float4(min(depth / (2.0f * R_ESCAPE), 1.0f), 0.0f, 0.0f, 0.0f), local);
        motionOut.write(half4(half2(motion), 0.0h, 0.0h), local);
    }
    uint over = (active && drift > u.driftBudget) ? 1u : 0u;
    uint exhausted = (active && outcome == RayExhausted) ? 1u : 0u;
    uint captured = (active && outcome == RayCaptured) ? 1u : 0u;
    uint rays = active ? 1u : 0u;
    uint sumRays = simd_sum(rays);
    uint sumOver = simd_sum(over);
    uint sumExhausted = simd_sum(exhausted);
    uint sumCaptured = simd_sum(captured);
    if (simd_is_first()) {
        atomic_fetch_add_explicit(&counters[0], sumRays, memory_order_relaxed);
        atomic_fetch_add_explicit(&counters[1], sumOver, memory_order_relaxed);
        atomic_fetch_add_explicit(&counters[2], sumExhausted, memory_order_relaxed);
        atomic_fetch_add_explicit(&counters[3], sumCaptured, memory_order_relaxed);
    }
}

kernel void probeRays(device const RayProbe* probes [[buffer(0)]],
                      device RayProbeResult* results [[buffer(1)]],
                      constant MarchUniforms& u [[buffer(2)]],
                      constant uint& count [[buffer(3)]],
                      texture3d<half, access::sample> emission [[texture(2)]],
                      texture3d<half, access::sample> velocity [[texture(3)]],
                      texture1d<half, access::sample> blackbody [[texture(4)]],
                      texture1d<float, access::sample> sphereSweep [[texture(7)]],
                      texture1d<float, access::sample> cameraSweep [[texture(8)]],
                      texture1d<float, access::sample> skySweep [[texture(9)]],
                      uint i [[thread_position_in_grid]]) {
    if (i >= count) return;
    RayProbe probe = probes[i];
    PreparedRay prepared = prepareRay(float3(probe.origin), float3(probe.direction), u, sphereSweep, cameraSweep, skySweep);
    RayProbeResult r;
    if (prepared.skyOnly) {
        r.position = rayPosition(prepared.ray);
        r.direction = prepared.sky;
        r.drift = 0.0f;
        r.outcome = RayEscaped;
        r.steps = 0u;
        r.energy = prepared.ray.energy;
        r.angularMomentum = prepared.ray.angularMomentum;
        results[i] = r;
        return;
    }
    PlaneRay ray;
    MarchResult m = marchRay(prepared.ray, u, false, emission, velocity, ray);
    r.position = rayPosition(ray);
    r.direction = (m.outcome == RayEscaped && !rayFallsIn(ray, m.outcome)) ? skyDirection(ray, m, u, sphereSweep) : rayDirection(ray);
    r.drift = m.drift;
    r.outcome = m.outcome;
    r.steps = m.steps;
    r.energy = rayEnergy(ray.s);
    r.angularMomentum = rayAngularMomentum(ray.s);
    results[i] = r;
}
