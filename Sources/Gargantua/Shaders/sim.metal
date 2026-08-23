#include "Common.h"

// Particle pass. One thread per particle, reads and writes its own slot only,
// no atomics, no cross thread reads, so a seed reproduces the buffer exactly.

static Particle spawn(uint index, uint event, constant SimUniforms& u, constant float* inverseCdf, bool fromDisk) {
    uint4 h0 = pcg4d(uint4(index, event, u.seed.x, u.seed.y));
    uint4 h1 = pcg4d(uint4(index, event, u.seed.x ^ 0x9E3779B9u, u.seed.y));
    float u0 = unitFloat(h0.x), u1 = unitFloat(h0.y), u2 = unitFloat(h0.z), u3 = unitFloat(h0.w);
    float u4 = unitFloat(h1.x), u5 = unitFloat(h1.y);

    float r;
    if (fromDisk) {
        float position = u0 * float(u.inverseCdfCount - 1u);
        uint k = min(uint(position), u.inverseCdfCount - 2u);
        r = mix(inverseCdf[k], inverseCdf[k + 1u], position - float(k));
    } else {
        float inner = R_FEED_INNER * R_FEED_INNER;
        float outer = R_DISK_OUTER * R_DISK_OUTER;
        r = sqrt(mix(inner, outer, u0));
    }
    float phi = 2.0f * M_PI_F * u1;
    float2 g01 = gaussianPair(u2, u3);
    float2 g23 = gaussianPair(u4, u5);
    float vc = circularSpeed(r, u.potential);
    float3 tangent = float3(-sin(phi), cos(phi), 0.0f);

    Particle p;
    p.position = float3(r * cos(phi), r * sin(phi), DISK_ASPECT * r * g01.x);
    p.velocity = vc * tangent + FEED_VELOCITY_DISPERSION * vc * float3(g01.y, g23.x, g23.y);
    p.temperature = u.temperatureScale * diskShape(r);
    p.respawns = event;
    return p;
}

kernel void seedParticles(device Particle* particles [[buffer(0)]],
                          constant SimUniforms& u [[buffer(1)]],
                          constant float* inverseCdf [[buffer(2)]],
                          uint i [[thread_position_in_grid]]) {
    if (i >= u.particleCount) return;
    particles[i] = spawn(i, 0u, u, inverseCdf, true);
}

kernel void stepParticles(device Particle* particles [[buffer(0)]],
                          constant SimUniforms& u [[buffer(1)]],
                          constant float* inverseCdf [[buffer(2)]],
                          uint i [[thread_position_in_grid]]) {
    if (i >= u.particleCount) return;
    Particle p = particles[i];
    float3 position = p.position;
    float3 velocity = p.velocity;
    for (uint s = 0u; s < SIM_SUBSTEPS; ++s) {
        float r = length(position);
        float3 gravity = position * (-potentialGradient(r, u.potential) / r);
        float omega = angularFrequency(r, u.potential);
        velocity += gravity * u.dt;
        velocity -= velocity * (u.alpha * omega * u.dt);
        position += velocity * u.dt;
        r = length(position);
        if (r < R_CAPTURE || r > R_ESCAPE) {
            p = spawn(i, p.respawns + 1u, u, inverseCdf, false);
            position = p.position;
            velocity = p.velocity;
        }
    }
    p.position = position;
    p.velocity = velocity;
    p.temperature = u.temperatureScale * diskShape(length(position));
    particles[i] = p;
}
