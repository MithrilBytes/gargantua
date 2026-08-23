// Null geodesics of Schwarzschild in ingoing Eddington and Finkelstein
// coordinates, reduced to each ray's orbital plane. Mirrors
// Sources/Oracle/Schwarzschild.swift line for line, in single precision.
#ifndef GARGANTUA_GEODESIC_H
#define GARGANTUA_GEODESIC_H

#include "Common.h"

struct RayState {
    float v, r, phi, vDot, rDot, phiDot;
};

struct PlaneRay {
    RayState s;
    float3 e1;
    float3 e2;
    float energy;
    float angularMomentum;
};

static inline float schwarzschildF(float r) {
    return 1.0f - R_SCHWARZSCHILD / r;
}

static inline RayState rayAdd(RayState a, RayState b) {
    return RayState { a.v + b.v, a.r + b.r, a.phi + b.phi, a.vDot + b.vDot, a.rDot + b.rDot, a.phiDot + b.phiDot };
}

static inline RayState rayScale(RayState a, float s) {
    return RayState { a.v * s, a.r * s, a.phi * s, a.vDot * s, a.rDot * s, a.phiDot * s };
}

static inline float rayEnergy(RayState s) {
    return schwarzschildF(s.r) * s.vDot - s.rDot;
}

static inline float rayAngularMomentum(RayState s) {
    return s.r * s.r * s.phiDot;
}

// Euler Lagrange equations of L = (1/2)(-f vDot^2 + 2 vDot rDot + r^2 phiDot^2).
static inline RayState rayDerivative(RayState s) {
    float r = s.r;
    float r2 = r * r;
    float vDotDot = -s.vDot * s.vDot / r2 + r * s.phiDot * s.phiDot;
    float rDotDot = 2.0f * s.rDot * s.vDot / r2 + schwarzschildF(r) * (r * s.phiDot * s.phiDot - s.vDot * s.vDot / r2);
    float phiDotDot = -2.0f * s.rDot * s.phiDot / r;
    return RayState { s.vDot, s.rDot, s.phiDot, vDotDot, rDotDot, phiDotDot };
}

// Classical fourth order Runge Kutta.
static inline RayState rayStep(RayState s, float h) {
    RayState k1 = rayDerivative(s);
    RayState k2 = rayDerivative(rayAdd(s, rayScale(k1, 0.5f * h)));
    RayState k3 = rayDerivative(rayAdd(s, rayScale(k2, 0.5f * h)));
    RayState k4 = rayDerivative(rayAdd(s, rayScale(k3, h)));
    RayState sum = rayAdd(rayAdd(k1, rayScale(k2, 2.0f)), rayAdd(rayScale(k3, 2.0f), k4));
    return rayAdd(s, rayScale(sum, h / 6.0f));
}

// Launch from a point in a direction measured by a static observer there,
// with the affine parameter scaled so the local photon energy is one.
static inline PlaneRay launchRay(float3 origin, float3 direction) {
    float r0 = length(origin);
    float3 e1 = origin / r0;
    float3 unit = normalize(direction);
    float dr = dot(unit, e1);
    float3 perpendicular = unit - dr * e1;
    float dphi = length(perpendicular);
    float3 e2;
    if (dphi < 1e-6f) {
        float3 helper = abs(e1.x) < 0.9f ? float3(1.0f, 0.0f, 0.0f) : float3(0.0f, 1.0f, 0.0f);
        e2 = normalize(helper - dot(helper, e1) * e1);
        dphi = 0.0f;
    } else {
        e2 = perpendicular / dphi;
    }
    float f0 = schwarzschildF(r0);
    float root = sqrt(f0);
    PlaneRay ray;
    ray.s = RayState { 0.0f, r0, 0.0f, (1.0f + dr) / root, root * dr, dphi / r0 };
    ray.e1 = e1;
    ray.e2 = e2;
    ray.energy = rayEnergy(ray.s);
    ray.angularMomentum = rayAngularMomentum(ray.s);
    return ray;
}

static inline float3 rayPosition(PlaneRay ray) {
    return ray.s.r * (cos(ray.s.phi) * ray.e1 + sin(ray.s.phi) * ray.e2);
}

// Spatial direction measured by a static observer at the ray's radius.
static inline float3 rayDirection(PlaneRay ray) {
    float3 radial = cos(ray.s.phi) * ray.e1 + sin(ray.s.phi) * ray.e2;
    float3 tangential = -sin(ray.s.phi) * ray.e1 + cos(ray.s.phi) * ray.e2;
    float3 local = ray.s.rDot / sqrt(max(schwarzschildF(ray.s.r), 1e-6f)) * radial + ray.s.r * ray.s.phiDot * tangential;
    float len = length(local);
    return len > 0.0f ? local / len : radial;
}

static inline float rayStepLength(float r, GeodesicSettings g) {
    return clamp(g.stepFactor * r, g.stepMin, g.stepMax);
}

// Largest relative deviation of E or L from the launch values.
static inline float rayDrift(PlaneRay ray) {
    float eDrift = abs(rayEnergy(ray.s) - ray.energy) / abs(ray.energy);
    float lDrift = abs(rayAngularMomentum(ray.s) - ray.angularMomentum) / max(abs(ray.angularMomentum), 1e-3f);
    return max(eDrift, lDrift);
}

#endif
