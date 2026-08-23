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

// Procedural stars: a cube map of cells, each holding at most one star
// whose presence, offset, brightness and temperature come from pcg4d.
static float3 starfield(float3 direction, uint seed,
                        texture1d<half, access::sample> blackbody) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float3 a = abs(direction);
    uint face;
    float2 st;
    float major;
    if (a.x >= a.y && a.x >= a.z) { face = direction.x > 0.0f ? 0u : 1u; st = direction.yz; major = a.x; }
    else if (a.y >= a.z) { face = direction.y > 0.0f ? 2u : 3u; st = direction.xz; major = a.y; }
    else { face = direction.z > 0.0f ? 4u : 5u; st = direction.xy; major = a.z; }
    st = st / major * 0.5f + 0.5f;
    const float cells = 96.0f;
    float2 scaled = st * cells;
    uint2 cell = uint2(min(scaled, cells - 1.0f));
    uint4 h = pcg4d(uint4(cell.x, cell.y, face, seed));
    if (h.x > 0x30000000u) return float3(0.0f);
    float2 offset = float2(unitFloat(h.y), unitFloat(h.z));
    float2 d = scaled - (float2(cell) + offset);
    float falloff = exp(-dot(d, d) * 40.0f);
    float brightness = pow(unitFloat(h.w), 3.0f) * falloff;
    float temperature = mix(3000.0f, 12000.0f, unitFloat(h.w ^ h.y));
    float3 tint = float3(blackbody.sample(linearClamp, blackbodyCoordinate(temperature)).rgb);
    return tint * brightness;
}

// Total redshift factor g = E_observed / E_emitted for light leaving gas
// that a static observer sees moving with velocity `gas`, reaching a
// distant observer: the gravitational factor sqrt(f) times the Doppler
// factor 1 / (gamma (1 - n . beta)), where n is the photon's direction of
// travel, opposite to the marched direction. The simulated velocity is treated as
// that locally measured velocity after a smooth compression below c,
// because the pseudo Newtonian orbits exceed c inside r of about 4.
// Mirrors Oracle/Schwarzschild.swift redshiftFactor.
static inline float redshiftFactor(float f, float3 direction, float3 gas) {
    float speed = length(gas);
    float beta = speed > 0.0f ? GAS_SPEED_CEILING * tanh(speed / GAS_SPEED_CEILING) : 0.0f;
    float3 velocity = speed > 0.0f ? gas * (beta / speed) : float3(0.0f);
    float gamma = rsqrt(1.0f - beta * beta);
    return sqrt(max(f, 0.0f)) / (gamma * (1.0f + dot(direction, velocity)));
}

struct MarchResult {
    float3 color;
    float drift;
    uint steps;
    uint outcome;
};

// The shared integration loop. `gather` is false for the validation probes,
// which only care about the geodesic.
static MarchResult marchRay(float3 origin, float3 direction, constant MarchUniforms& u, bool gather,
                            texture3d<half, access::sample> emission,
                            texture3d<half, access::sample> velocity,
                            texture1d<half, access::sample> blackbody,
                            thread PlaneRay& rayOut) {
    PlaneRay ray = launchRay(origin, direction);
    float3 color = float3(0.0f);
    float transmittance = 1.0f;
    float3 previous = rayPosition(ray);
    uint outcome = RayExhausted;
    uint steps = 0u;
    for (uint k = 0u; k < STEP_CAP_STILL; ++k) {
        if (k >= u.geodesic.stepCap) break;
        float h = rayStepLength(ray.s.r, u.geodesic);
        ray.s = rayStep(ray.s, h);
        steps = k + 1u;
        float3 position = rayPosition(ray);
        if (ray.s.r <= u.geodesic.captureRadius) { outcome = RayCaptured; break; }
        if (gather && abs(position.z) < DISK_SLAB_HALF_HEIGHT && all(abs(position.xy) < u.volumeHalfExtent) && transmittance > 0.004f) {
            Sample s = sampleVolume(position, u.volumeHalfExtent, emission, velocity);
            if (s.density > 0.0f) {
                float pathLength = length(position - previous);
                float g3 = 1.0f;
                if (u.redshift != 0u) {
                    float g = redshiftFactor(schwarzschildF(ray.s.r), rayDirection(ray), s.velocity);
                    g3 = g * g * g;
                }
                float alpha = 1.0f - exp(-u.opacityScale * s.density * pathLength);
                color += transmittance * s.emission * g3 * pathLength;
                transmittance *= 1.0f - alpha;
            }
        }
        previous = position;
        if (ray.s.r >= u.geodesic.escapeRadius) { outcome = RayEscaped; break; }
    }
    if (gather && outcome != RayCaptured) {
        // Exhausted rays are counted by the caller; shading the sky along
        // their last direction is the least wrong thing to draw for them.
        color += transmittance * u.starBrightness * starfield(rayDirection(ray), u.starSeed, blackbody);
    }
    rayOut = ray;
    MarchResult result;
    result.color = color;
    result.drift = rayDrift(ray);
    result.steps = steps;
    result.outcome = outcome;
    return result;
}

kernel void marchImage(texture2d<half, access::write> output [[texture(0)]],
                       texture2d<half, access::write> debug [[texture(1)]],
                       texture3d<half, access::sample> emission [[texture(2)]],
                       texture3d<half, access::sample> velocity [[texture(3)]],
                       texture1d<half, access::sample> blackbody [[texture(4)]],
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
        float2 ndc = float2((2.0f * (float(pixel.x) + 0.5f) / float(u.resolution.x) - 1.0f) * u.tanHalfFov.x,
                            (1.0f - 2.0f * (float(pixel.y) + 0.5f) / float(u.resolution.y)) * u.tanHalfFov.y);
        float3 direction = normalize(u.cameraForward + ndc.x * u.cameraRight + ndc.y * u.cameraUp);
        PlaneRay ray;
        MarchResult m = marchRay(u.cameraPosition, direction, u, true, emission, velocity, blackbody, ray);
        color = m.color;
        drift = m.drift;
        steps = m.steps;
        outcome = m.outcome;
        output.write(half4(half3(color), 1.0h), local);
        debug.write(half4(half(drift), half(float(steps)), half(float(outcome)), 1.0h), local);
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
                      uint i [[thread_position_in_grid]]) {
    if (i >= count) return;
    RayProbe probe = probes[i];
    PlaneRay ray;
    MarchResult m = marchRay(float3(probe.origin), float3(probe.direction), u, false, emission, velocity, blackbody, ray);
    RayProbeResult r;
    r.position = rayPosition(ray);
    r.direction = rayDirection(ray);
    r.drift = m.drift;
    r.outcome = m.outcome;
    r.steps = m.steps;
    r.energy = rayEnergy(ray.s);
    r.angularMomentum = rayAngularMomentum(ray.s);
    results[i] = r;
}
