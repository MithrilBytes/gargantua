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

// Table coordinate for an impact parameter; tables are sampled at
// b = low + (high - low) (1 - (1 - t)^2). Mirrors Oracle/Deflection.swift.
// Entry i of a table sits at t = i / (N - 1); the sampler puts it at
// (i + 0.5) / N, so the coordinate is remapped before sampling.
static inline float sweepCoordinate(float low, float high, float b) {
    float x = clamp((b - low) / (high - low), 0.0f, 1.0f);
    float t = 1.0f - sqrt(1.0f - x);
    return (t * (SWEEP_TABLE_SIZE - 1.0f) + 0.5f) / SWEEP_TABLE_SIZE;
}

// Direction of travel at infinity for a ray whose azimuth tends to phi.
static inline float3 asymptoticDirection(PlaneRay ray, float phi) {
    return cos(phi) * ray.e1 + sin(phi) * ray.e2;
}

struct PreparedRay {
    PlaneRay ray;
    /// True when the ray never enters the sphere: shade the sky along
    /// `sky` and skip the integration.
    bool skyOnly;
    float3 sky;
};

// Skip the empty leg between the camera and the integration sphere. Rays
// that never reach the sphere get their asymptotic direction from the sky
// table; the rest are placed exactly on the sphere with their conserved
// energy and angular momentum. Impact parameters are never negative here
// because launchRay orients the plane along the ray's turn.
static inline PreparedRay prepareRay(float3 origin, float3 direction, constant MarchUniforms& u,
                                     texture1d<float, access::sample> sphereSweep,
                                     texture1d<float, access::sample> cameraSweep,
                                     texture1d<float, access::sample> skySweep) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    PreparedRay p;
    p.ray = launchRay(origin, direction);
    p.skyOnly = false;
    p.sky = float3(0.0f);
    if (u.sphereRadius <= 0.0f || p.ray.s.r <= u.sphereRadius) return p;
    float b = abs(p.ray.angularMomentum) / p.ray.energy;
    if (p.ray.s.rDot >= 0.0f) {
        float sweep = cameraSweep.sample(linearClamp, sweepCoordinate(0.0f, u.cameraMaxB, b)).r;
        p.skyOnly = true;
        p.sky = asymptoticDirection(p.ray, p.ray.s.phi + sweep);
        return p;
    }
    if (b >= u.sphereMaxB) {
        float sweep = skySweep.sample(linearClamp, sweepCoordinate(u.skyMinB, u.skyMaxB, b)).r;
        p.skyOnly = true;
        p.sky = asymptoticDirection(p.ray, p.ray.s.phi + sweep);
        return p;
    }
    float sweep = sphereSweep.sample(linearClamp, sweepCoordinate(0.0f, u.sphereTableMaxB, b)).r - cameraSweep.sample(linearClamp, sweepCoordinate(0.0f, u.cameraMaxB, b)).r;
    float r = u.sphereRadius;
    float f = schwarzschildF(r);
    float E = p.ray.energy;
    float L = p.ray.angularMomentum;
    float phiDot = L / (r * r);
    float rDot = -sqrt(max(E * E - f * L * L / (r * r), 0.0f));
    float vDot = (E + rDot) / f;
    p.ray.s = RayState { 0.0f, r, p.ray.s.phi + sweep, vDot, rDot, phiDot };
    return p;
}

// Sky direction for a ray that left the sphere moving outward.
static inline float3 sphereExitDirection(PlaneRay ray, constant MarchUniforms& u,
                                         texture1d<float, access::sample> sphereSweep) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float b = abs(ray.angularMomentum) / ray.energy;
    float sweep = sphereSweep.sample(linearClamp, sweepCoordinate(0.0f, u.sphereTableMaxB, b)).r;
    return asymptoticDirection(ray, ray.s.phi + sweep);
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

#endif
