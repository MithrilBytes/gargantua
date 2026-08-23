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
constant float MASS_FIXED = 256.0f;

static inline uint voxelIndex(uint3 c, uint n) {
    return (c.z * n + c.y) * n + c.x;
}

static inline void deposit(device atomic_uint* emission, device atomic_int* momentum, device atomic_uint* mass,
                           uint index, float weight, float energy, float relative, float3 velocity) {
    uint fixedEnergy = uint(energy * weight * ENERGY_FIXED + 0.5f);
    uint fixedEnergyT = uint(energy * relative * weight * ENERGY_T_FIXED + 0.5f);
    int3 fixedMomentum = int3(rint(velocity * (weight * MOMENTUM_FIXED)));
    uint fixedMass = uint(weight * MASS_FIXED + 0.5f);
    atomic_fetch_add_explicit(&emission[2u * index + 0u], fixedEnergy, memory_order_relaxed);
    atomic_fetch_add_explicit(&emission[2u * index + 1u], fixedEnergyT, memory_order_relaxed);
    atomic_fetch_add_explicit(&momentum[3u * index + 0u], fixedMomentum.x, memory_order_relaxed);
    atomic_fetch_add_explicit(&momentum[3u * index + 1u], fixedMomentum.y, memory_order_relaxed);
    atomic_fetch_add_explicit(&momentum[3u * index + 2u], fixedMomentum.z, memory_order_relaxed);
    atomic_fetch_add_explicit(&mass[index], fixedMass, memory_order_relaxed);
}

// Cloud in cell deposit in the space of voxel centers, matching the
// trilinear reconstruction the march samples with. Hockney and Eastwood
// 1988, ch. 5. A particle binned to its nearest voxel pops one whole voxel
// when it crosses a boundary, which reads as pulsing dots wherever a voxel
// holds a single particle; the cloud moves continuously instead.
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

    float relative = p.temperature / u.peakTemperature;
    float energy = relative * relative * relative * relative * u.emissionScale;
    float3 velocity = float3(p.velocity);

    float3 grid = unitCube * float(u.volumeSize) - 0.5f;
    float3 base = floor(grid);
    float3 fraction = grid - base;
    int3 low = int3(base);
    int3 high = min(low + 1, int(u.volumeSize) - 1);
    low = max(low, 0);

    if (u.exactDeposit != 0u) {
        for (uint c = 0u; c < CIC_CORNERS; ++c) {
            int3 corner = int3((c & 1u) != 0u ? high.x : low.x,
                               (c & 2u) != 0u ? high.y : low.y,
                               (c & 4u) != 0u ? high.z : low.z);
            float3 w3 = mix(1.0f - fraction, fraction, float3((c & 1u) != 0u, (c & 2u) != 0u, (c & 4u) != 0u));
            float w = w3.x * w3.y * w3.z;
            if (w <= 0.0f) continue;
            deposit(emission, momentum, mass, voxelIndex(uint3(corner), u.volumeSize), w, energy, relative, velocity);
        }
    } else {
        // One corner, chosen with the trilinear weights as probabilities.
        // Unbiased: the expected deposit equals the exact one; dense voxels
        // average over their particles and sparse ones over frames.
        uint4 h = pcg4d(uint4(i, u.frame, u.seed.x, u.seed.y));
        float3 pick = float3(unitFloat(h.x), unitFloat(h.y), unitFloat(h.z));
        int3 corner = int3(pick.x < fraction.x ? high.x : low.x,
                           pick.y < fraction.y ? high.y : low.y,
                           pick.z < fraction.z ? high.z : low.z);
        deposit(emission, momentum, mass, voxelIndex(uint3(corner), u.volumeSize), 1.0f, energy, relative, velocity);
    }
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

    float count = float(mass[index]) / MASS_FIXED;
    float energy = float(emission[2u * index + 0u]) / ENERGY_FIXED;
    float energyT = float(emission[2u * index + 1u]) / ENERGY_T_FIXED;
    float3 tint = float3(0.0f);
    if (energy > 0.0f) {
        float meanTemperature = energyT / energy * u.peakTemperature;
        tint = float3(blackbody.sample(linearClamp, blackbodyCoordinate(meanTemperature)).rgb);
    }
    float3 m = float3(float(momentum[3u * index + 0u]), float(momentum[3u * index + 1u]), float(momentum[3u * index + 2u])) / MOMENTUM_FIXED;
    float density = count * inverseVolume;
    float3 velocity = count > 0.0f ? m / count : float3(0.0f);
    emissionOut.write(half4(half3(tint * energy * inverseVolume), half(density)), cell);
    velocityOut.write(half4(half3(velocity), 1.0h), cell);
}
