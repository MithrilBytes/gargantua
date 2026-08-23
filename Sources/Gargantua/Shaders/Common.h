// Helpers shared by the kernels. Metal only.
#ifndef GARGANTUA_COMMON_H
#define GARGANTUA_COMMON_H

#include <metal_stdlib>
#include "ShaderTypes.h"
#include "Constants.h"
using namespace metal;

// pcg4d from Jarzynski and Olano 2020, JCGT 9(3), 20. Mirrors Oracle/Hash.swift.
static inline uint4 pcg4d(uint4 v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.w; v.y += v.z * v.x; v.z += v.x * v.y; v.w += v.y * v.z;
    v ^= v >> 16u;
    v.x += v.y * v.w; v.y += v.z * v.x; v.z += v.x * v.y; v.w += v.y * v.z;
    return v;
}

// Uniform in [0, 1) from the top 24 bits, exact in single precision.
static inline float unitFloat(uint x) {
    return float(x >> 8u) * (1.0f / 16777216.0f);
}

// Box and Muller 1958.
static inline float2 gaussianPair(float u1, float u2) {
    float radius = sqrt(-2.0f * log(1.0f - u1));
    float angle = 2.0f * M_PI_F * u2;
    return float2(radius * cos(angle), radius * sin(angle));
}

// d Phi / d r for the selected potential; mirrors Oracle/Potential.swift.
static inline float potentialGradient(float r, uint potential) {
    if (potential == PotentialPaczynskiWiita) {
        float d = max(r - R_SCHWARZSCHILD, 1e-6f);
        return 1.0f / (d * d);
    }
    return 1.0f / (r * r);
}

static inline float circularSpeed(float r, uint potential) {
    return sqrt(r * potentialGradient(r, potential));
}

static inline float angularFrequency(float r, uint potential) {
    return circularSpeed(r, potential) / r;
}

// Unnormalized thin disk profile; mirrors Oracle/DiskModel.swift.
static inline float diskShape(float r) {
    float x = R_ISCO / r;
    float torque = max(1.0f - sqrt(x), ZERO_TORQUE_FLOOR);
    return pow(x, 0.75f) * pow(torque, 0.25f);
}

// Blackbody table coordinate, log spaced; mirrors Oracle/Blackbody.swift.
static inline float blackbodyCoordinate(float temperature) {
    float t = clamp(temperature, BLACKBODY_T_MIN, BLACKBODY_T_MAX);
    return (log(t) - log(BLACKBODY_T_MIN)) / (log(BLACKBODY_T_MAX) - log(BLACKBODY_T_MIN));
}

#endif
