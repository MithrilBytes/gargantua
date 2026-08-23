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
    unsigned int debugView;
    float driftBudget;
} PresentUniforms;

/// Geodesic integration policy, shared by the image kernel and the probes.
typedef struct {
    float stepFactor;
    float stepMin;
    float stepMax;
    float captureRadius;
    float escapeRadius;
    unsigned int stepCap;
    float padding0;
    float padding1;
} GeodesicSettings;

enum {
    RayCaptured = 0,
    RayEscaped = 1,
    RayExhausted = 2
};

/// One ray integrated outside the image path, for validation.
typedef struct {
    packed3 origin;
    packed3 direction;
} RayProbe;

typedef struct {
    packed3 position;
    packed3 direction;
    float drift;
    unsigned int outcome;
    unsigned int steps;
    float energy;
    float angularMomentum;
} RayProbeResult;

typedef struct {
    unsigned int volumeSize;
    unsigned int particleCount;
    float halfExtent;
    float peakTemperature;
    float emissionScale;
    float padding0;
    float padding1;
    float padding2;
} SplatUniforms;

typedef struct {
    simd_float3 cameraPosition;
    simd_float3 cameraRight;
    simd_float3 cameraUp;
    simd_float3 cameraForward;
    /// tan(fov / 2) scaled by aspect in x.
    simd_float2 tanHalfFov;
    /// Full image size in pixels.
    simd_uint2 resolution;
    /// Pixel offset of the tile being rendered.
    simd_uint2 tileOrigin;
    float volumeHalfExtent;
    float opacityScale;
    float starBrightness;
    float driftBudget;
    unsigned int starSeed;
    unsigned int redshift;
    /// Minimum path length between stored samples when baking.
    float bakeSpacing;
    unsigned int bakeCapacity;
    /// Subpixel sample offset in input pixels, for temporal upscaling.
    simd_float2 jitter;
    /// Previous frame's camera, for motion vectors by straight line reprojection.
    simd_float3 previousPosition;
    simd_float3 previousRight;
    simd_float3 previousUp;
    simd_float3 previousForward;
    GeodesicSettings geodesic;
} MarchUniforms;

/// One baked ray: how many samples it stored and how it ended.
typedef struct {
    unsigned int count;
    /// 1 when the ray falls into the hole, 0 when it sees the sky.
    unsigned int fallsIn;
    /// Final direction as three halves plus depth as a half, packed.
    unsigned int directionXY;
    unsigned int directionZDepth;
} BakedRay;

/// Per frame ray statistics, summed by the march kernel.
typedef struct {
    unsigned int rays;
    unsigned int overDriftBudget;
    unsigned int exhausted;
    unsigned int captured;
} MarchCounters;

#endif
