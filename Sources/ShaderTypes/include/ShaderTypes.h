// Types shared between the Swift host and the Metal shaders.
// Included by Swift through the ShaderTypes module and by every .metal file.
#ifndef GARGANTUA_SHADER_TYPES_H
#define GARGANTUA_SHADER_TYPES_H

#include <simd/simd.h>

#ifdef __METAL_VERSION__
typedef packed_float3 packed3;
#else
typedef struct { float x, y, z; } packed3;
#endif

/// One test particle. 32 bytes, so one million particles cost 32 MB.
typedef struct {
    packed3 position;
    packed3 velocity;
    float temperature;
    unsigned int respawns;
} Particle;

enum {
    PotentialNewtonian = 0,
    PotentialPaczynskiWiita = 1
};

typedef struct {
    simd_uint2 seed;
    unsigned int particleCount;
    unsigned int potential;
    unsigned int inverseCdfCount;
    float dt;
    float alpha;
    /// Peak temperature divided by the unnormalized profile at its peak.
    float temperatureScale;
} SimUniforms;

typedef struct {
    simd_float4x4 viewProjection;
    simd_float2 viewport;
    /// viewport height / (2 tan(fov / 2)); divide by depth for pixels per world unit.
    float pixelsPerUnit;
    float spriteRadius;
    float exposure;
    float peakTemperature;
    float padding0;
    float padding1;
} SpriteUniforms;

typedef struct {
    /// Hud quad corners in normalized device coordinates: x0, y0, x1, y1.
    simd_float4 hudRect;
    float exposure;
    unsigned int hudVisible;
    float padding0;
    float padding1;
} PresentUniforms;

#endif
