#include "Common.h"

// Pass 2. Particles are binned into a cube of half extent VOLUME_HALF_EXTENT
// as fixed point integer sums, then resolved into half precision textures.
// Accumulation order is not deterministic, which is why the splat is
// excluded from the determinism golden.
//
// The bin sums energy and energy weighted temperature rather than three
// tinted channels; the blackbody tint is applied at resolve from the mean
// temperature. Within one voxel the temperature spread is a few hundred
// kelvin, far below a visible tint difference, and the sum costs two
// atomics instead of three. The resolve reads the sums as plain integers,
// legal because dispatches in one encoder are ordered, and a blit fill
// zeroes them for the next frame.

constant float ENERGY_FIXED = 16777216.0f;
constant float ENERGY_T_FIXED = 1048576.0f;
constant float MOMENTUM_FIXED = 4096.0f;

static inline uint voxelIndex(uint3 c, uint n) {
    return (c.z * n + c.y) * n + c.x;
}

kernel void splatParticles(device const Particle* particles [[buffer(0)]],
                           device atomic_uint* emission [[buffer(1)]],
                           device atomic_int* momentum [[buffer(2)]],
                           device atomic_uint* mass [[buffer(3)]],
                           constant SplatUniforms& u [[buffer(4)]],
                           uint i [[thread_position_in_grid]]) {
    if (i >= u.particleCount) return;
    Particle p = particles[i];
    float3 position = float3(p.position);
    float3 unitCube = (position + u.halfExtent) / (2.0f * u.halfExtent);
    if (any(unitCube < 0.0f) || any(unitCube >= 1.0f)) return;
    uint3 cell = uint3(unitCube * float(u.volumeSize));
    cell = min(cell, uint3(u.volumeSize - 1u));
    uint index = voxelIndex(cell, u.volumeSize);

    float relative = p.temperature / u.peakTemperature;
    float energy = relative * relative * relative * relative * u.emissionScale;
    uint fixedEnergy = uint(energy * ENERGY_FIXED);
    uint fixedEnergyT = uint(energy * relative * ENERGY_T_FIXED);
    int3 fixedMomentum = int3(float3(p.velocity) * MOMENTUM_FIXED);

    atomic_fetch_add_explicit(&emission[2u * index + 0u], fixedEnergy, memory_order_relaxed);
    atomic_fetch_add_explicit(&emission[2u * index + 1u], fixedEnergyT, memory_order_relaxed);
    atomic_fetch_add_explicit(&momentum[3u * index + 0u], fixedMomentum.x, memory_order_relaxed);
    atomic_fetch_add_explicit(&momentum[3u * index + 1u], fixedMomentum.y, memory_order_relaxed);
    atomic_fetch_add_explicit(&momentum[3u * index + 2u], fixedMomentum.z, memory_order_relaxed);
    atomic_fetch_add_explicit(&mass[index], 1u, memory_order_relaxed);
}

// Converts the sums into emission per unit volume (rgb, with particle
// density in alpha) and mean velocity. The sums are zeroed afterwards by a
// blit fill, not here.
kernel void resolveVolume(device const uint* emission [[buffer(1)]],
                          device const int* momentum [[buffer(2)]],
                          device const uint* mass [[buffer(3)]],
                          constant SplatUniforms& u [[buffer(4)]],
                          texture3d<half, access::write> emissionOut [[texture(0)]],
                          texture3d<half, access::write> velocityOut [[texture(1)]],
                          texture1d<half, access::sample> blackbody [[texture(2)]],
                          uint3 cell [[thread_position_in_grid]]) {
    if (any(cell >= uint3(u.volumeSize))) return;
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    uint index = voxelIndex(cell, u.volumeSize);
    float voxel = 2.0f * u.halfExtent / float(u.volumeSize);
    float inverseVolume = 1.0f / (voxel * voxel * voxel);

    uint count = mass[index];
    float energy = float(emission[2u * index + 0u]) / ENERGY_FIXED;
    float energyT = float(emission[2u * index + 1u]) / ENERGY_T_FIXED;
    float3 tint = float3(0.0f);
    if (energy > 0.0f) {
        float meanTemperature = energyT / energy * u.peakTemperature;
        tint = float3(blackbody.sample(linearClamp, blackbodyCoordinate(meanTemperature)).rgb);
    }
    float3 m = float3(float(momentum[3u * index + 0u]), float(momentum[3u * index + 1u]), float(momentum[3u * index + 2u])) / MOMENTUM_FIXED;
    float density = float(count) * inverseVolume;
    float3 velocity = count > 0u ? m / float(count) : float3(0.0f);
    emissionOut.write(half4(half3(tint * energy * inverseVolume), half(density)), cell);
    velocityOut.write(half4(half3(velocity), 1.0h), cell);
}
