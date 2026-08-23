#include "Common.h"

// Pass 2. Particles are binned into a cube of half extent VOLUME_HALF_EXTENT
// as fixed point integer sums, then resolved into half precision textures.
// Accumulation order is not deterministic, which is why the splat is
// excluded from the determinism golden.

constant float EMISSION_FIXED = 65536.0f;
constant float MOMENTUM_FIXED = 4096.0f;

static inline uint voxelIndex(uint3 c, uint n) {
    return (c.z * n + c.y) * n + c.x;
}

kernel void splatParticles(device const Particle* particles [[buffer(0)]],
                           device atomic_uint* emission [[buffer(1)]],
                           device atomic_int* momentum [[buffer(2)]],
                           device atomic_uint* mass [[buffer(3)]],
                           constant SplatUniforms& u [[buffer(4)]],
                           texture1d<half, access::sample> blackbody [[texture(0)]],
                           uint i [[thread_position_in_grid]]) {
    if (i >= u.particleCount) return;
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    Particle p = particles[i];
    float3 position = float3(p.position);
    float3 unitCube = (position + u.halfExtent) / (2.0f * u.halfExtent);
    if (any(unitCube < 0.0f) || any(unitCube >= 1.0f)) return;
    uint3 cell = uint3(unitCube * float(u.volumeSize));
    cell = min(cell, uint3(u.volumeSize - 1u));
    uint index = voxelIndex(cell, u.volumeSize);

    float relative = p.temperature / u.peakTemperature;
    float energy = relative * relative * relative * relative * u.emissionScale;
    float3 tint = float3(blackbody.sample(linearClamp, blackbodyCoordinate(p.temperature)).rgb);
    uint3 fixedEmission = uint3(tint * energy * EMISSION_FIXED);
    int3 fixedMomentum = int3(float3(p.velocity) * MOMENTUM_FIXED);

    atomic_fetch_add_explicit(&emission[3u * index + 0u], fixedEmission.x, memory_order_relaxed);
    atomic_fetch_add_explicit(&emission[3u * index + 1u], fixedEmission.y, memory_order_relaxed);
    atomic_fetch_add_explicit(&emission[3u * index + 2u], fixedEmission.z, memory_order_relaxed);
    atomic_fetch_add_explicit(&momentum[3u * index + 0u], fixedMomentum.x, memory_order_relaxed);
    atomic_fetch_add_explicit(&momentum[3u * index + 1u], fixedMomentum.y, memory_order_relaxed);
    atomic_fetch_add_explicit(&momentum[3u * index + 2u], fixedMomentum.z, memory_order_relaxed);
    atomic_fetch_add_explicit(&mass[index], 1u, memory_order_relaxed);
}

// Converts the sums into emission per unit volume (rgb, with particle
// density in alpha) and mean velocity, then clears the sums for the next
// frame.
kernel void resolveVolume(device atomic_uint* emission [[buffer(1)]],
                          device atomic_int* momentum [[buffer(2)]],
                          device atomic_uint* mass [[buffer(3)]],
                          constant SplatUniforms& u [[buffer(4)]],
                          texture3d<half, access::write> emissionOut [[texture(0)]],
                          texture3d<half, access::write> velocityOut [[texture(1)]],
                          uint3 cell [[thread_position_in_grid]]) {
    if (any(cell >= uint3(u.volumeSize))) return;
    uint index = voxelIndex(cell, u.volumeSize);
    float voxel = 2.0f * u.halfExtent / float(u.volumeSize);
    float inverseVolume = 1.0f / (voxel * voxel * voxel);

    uint count = atomic_exchange_explicit(&mass[index], 0u, memory_order_relaxed);
    float3 e = float3(atomic_exchange_explicit(&emission[3u * index + 0u], 0u, memory_order_relaxed),
                      atomic_exchange_explicit(&emission[3u * index + 1u], 0u, memory_order_relaxed),
                      atomic_exchange_explicit(&emission[3u * index + 2u], 0u, memory_order_relaxed)) / EMISSION_FIXED;
    float3 m = float3(atomic_exchange_explicit(&momentum[3u * index + 0u], 0, memory_order_relaxed),
                      atomic_exchange_explicit(&momentum[3u * index + 1u], 0, memory_order_relaxed),
                      atomic_exchange_explicit(&momentum[3u * index + 2u], 0, memory_order_relaxed)) / MOMENTUM_FIXED;
    float density = float(count) * inverseVolume;
    float3 velocity = count > 0u ? m / float(count) : float3(0.0f);
    emissionOut.write(half4(half3(e * inverseVolume), half(density)), cell);
    velocityOut.write(half4(half3(velocity), 1.0h), cell);
}
