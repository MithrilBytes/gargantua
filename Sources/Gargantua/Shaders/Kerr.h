// Null geodesics of the Kerr metric in Boyer and Lindquist coordinates,
// single precision. Mirrors Sources/Oracle/KerrGeodesic.swift line for
// line: the separable Hamiltonian with conserved energy and axial angular
// momentum as parameters, the Carter constant and the null residual as the
// error gauges.
#ifndef GARGANTUA_KERR_H
#define GARGANTUA_KERR_H

#include "Geodesic.h"

struct KerrRayState {
    float r, theta, phi, pr, ptheta;
    float energy;
    float angularMomentum;
};

static inline float kerrOuterHorizon(float spin) {
    return 1.0f + sqrt(max(1.0f - spin * spin, 0.0f));
}

static inline float kerrDelta(float spin, float r) {
    return r * r - 2.0f * r + spin * spin;
}

static inline float kerrSigma(float spin, float r, float theta) {
    float c = cos(theta);
    return r * r + spin * spin * c * c;
}

static inline float2 kerrPotentials(float spin, KerrRayState s) {
    float p = (s.r * s.r + spin * spin) * s.energy - spin * s.angularMomentum;
    float sin2 = max(sin(s.theta) * sin(s.theta), 1e-8f);
    float g = s.angularMomentum * s.angularMomentum / sin2
            - 2.0f * spin * s.energy * s.angularMomentum
            + spin * spin * s.energy * s.energy * sin2;
    return float2(p, g);
}

static inline float kerrNullResidual(float spin, KerrRayState s) {
    float delta = kerrDelta(spin, s.r);
    float2 pg = kerrPotentials(spin, s);
    return delta * s.pr * s.pr + s.ptheta * s.ptheta - pg.x * pg.x / delta + pg.y;
}

static inline float kerrCarter(float spin, KerrRayState s) {
    float c = cos(s.theta);
    float sin2 = max(sin(s.theta) * sin(s.theta), 1e-8f);
    float term = s.angularMomentum * s.angularMomentum / sin2 - spin * spin * s.energy * s.energy;
    return s.ptheta * s.ptheta + c * c * term;
}

static inline KerrRayState kerrAdd(KerrRayState a, KerrRayState b) {
    a.r += b.r; a.theta += b.theta; a.phi += b.phi; a.pr += b.pr; a.ptheta += b.ptheta;
    return a;
}

static inline KerrRayState kerrScale(KerrRayState a, float f) {
    a.r *= f; a.theta *= f; a.phi *= f; a.pr *= f; a.ptheta *= f;
    return a;
}

// Hamilton's equations, exact including the off shell Sigma terms.
static inline KerrRayState kerrDerivative(float spin, KerrRayState s) {
    float r = s.r, theta = s.theta;
    float e = s.energy, l = s.angularMomentum;
    float delta = kerrDelta(spin, r);
    float sigma = kerrSigma(spin, r, theta);
    float deltaPrime = 2.0f * r - 2.0f;
    float sinTheta = sin(theta), cosTheta = cos(theta);
    float sin2 = max(sinTheta * sinTheta, 1e-8f);
    float2 pg = kerrPotentials(spin, s);
    float p = pg.x, g = pg.y;
    float f = delta * s.pr * s.pr + s.ptheta * s.ptheta - p * p / delta + g;
    float hamiltonian = f / (2.0f * sigma);

    float pPrime = 2.0f * r * e;
    float fr = deltaPrime * s.pr * s.pr - 2.0f * p * pPrime / delta + p * p * deltaPrime / (delta * delta);
    float ftheta = -2.0f * l * l * cosTheta / (sin2 * max(sinTheta, 1e-4f))
                 + 2.0f * spin * spin * e * e * sinTheta * cosTheta;
    float sigmaR = 2.0f * r;
    float sigmaTheta = -2.0f * spin * spin * sinTheta * cosTheta;

    KerrRayState out = s;
    out.r = delta * s.pr / sigma;
    out.theta = s.ptheta / sigma;
    out.phi = (spin * p / delta + l / sin2 - spin * e) / sigma;
    out.pr = -(fr / (2.0f * sigma) - hamiltonian * sigmaR / sigma);
    out.ptheta = -(ftheta / (2.0f * sigma) - hamiltonian * sigmaTheta / sigma);
    return out;
}

static inline KerrRayState kerrStep(float spin, KerrRayState s, float h) {
    KerrRayState k1 = kerrDerivative(spin, s);
    KerrRayState k2 = kerrDerivative(spin, kerrAdd(s, kerrScale(k1, 0.5f * h)));
    KerrRayState k3 = kerrDerivative(spin, kerrAdd(s, kerrScale(k2, 0.5f * h)));
    KerrRayState k4 = kerrDerivative(spin, kerrAdd(s, kerrScale(k3, h)));
    KerrRayState sum = kerrAdd(kerrAdd(k1, kerrScale(k2, 2.0f)), kerrAdd(kerrScale(k3, 2.0f), k4));
    return kerrAdd(s, kerrScale(sum, h / 6.0f));
}

static inline float kerrRadiusOf(float spin, float3 point) {
    float a2 = spin * spin;
    float rho2 = dot(point, point);
    float halved = 0.5f * (rho2 - a2);
    return sqrt(halved + sqrt(halved * halved + a2 * point.z * point.z));
}

// Launch along a locally measured direction, decomposed against the
// spherical frame; identical convention to the oracle.
static inline KerrRayState kerrLaunch(float spin, float3 origin, float3 direction) {
    float r = kerrRadiusOf(spin, origin);
    float rho = length(origin);
    float theta = acos(clamp(origin.z / rho, -1.0f, 1.0f));
    float phi = atan2(origin.y, origin.x);
    float3 d = normalize(direction);

    float sinTheta = sin(theta), cosTheta = cos(theta);
    float3 rHat = float3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);
    float3 thetaHat = float3(cosTheta * cos(phi), cosTheta * sin(phi), -sinTheta);
    float3 phiHat = float3(-sin(phi), cos(phi), 0.0f);
    float nr = dot(d, rHat);
    float ntheta = dot(d, thetaHat);
    float nphi = dot(d, phiHat);

    float delta = kerrDelta(spin, r);
    float sigma = kerrSigma(spin, r, theta);
    float sin2 = max(sinTheta * sinTheta, 1e-8f);
    float gtt = -(1.0f - 2.0f * r / sigma);
    float gtphi = -2.0f * spin * r * sin2 / sigma;
    float gphiphi = (r * r + spin * spin + 2.0f * spin * spin * r * sin2 / sigma) * sin2;
    float grr = sigma / delta;
    float gthth = sigma;

    float ut = 1.0f / sqrt(-gtt);
    float phiNorm = sqrt(gphiphi - gtphi * gtphi / gtt);
    float pt = ut + nphi * (-gtphi / gtt) / phiNorm;
    float pphi = nphi / phiNorm;

    KerrRayState s;
    s.r = r;
    s.theta = theta;
    s.phi = phi;
    s.energy = -(gtt * pt + gtphi * pphi);
    s.angularMomentum = gtphi * pt + gphiphi * pphi;
    s.pr = grr * (nr / sqrt(grr));
    s.ptheta = gthth * (ntheta / sqrt(gthth));
    return s;
}

static inline float3 kerrPosition(float spin, KerrRayState s) {
    float radial = sqrt(s.r * s.r + spin * spin);
    float sinTheta = sin(s.theta);
    return float3(radial * sinTheta * cos(s.phi), radial * sinTheta * sin(s.phi), s.r * cos(s.theta));
}

// Direction of travel against the spherical frame, unit length; the same
// convention the launch uses, shared with the oracle.
static inline float3 kerrDirection(float spin, KerrRayState s) {
    float delta = kerrDelta(spin, s.r);
    float sigma = kerrSigma(spin, s.r, s.theta);
    float sin2 = max(sin(s.theta) * sin(s.theta), 1e-8f);
    float rDot = delta * s.pr / sigma;
    float thetaDot = s.ptheta / sigma;
    float2 pg = kerrPotentials(spin, s);
    float phiDot = (spin * pg.x / delta + s.angularMomentum / sin2 - spin * s.energy) / sigma;
    float sinTheta = sin(s.theta), cosTheta = cos(s.theta);
    float3 rHat = float3(sinTheta * cos(s.phi), sinTheta * sin(s.phi), cosTheta);
    float3 thetaHat = float3(cosTheta * cos(s.phi), cosTheta * sin(s.phi), -sinTheta);
    float3 phiHat = float3(-sin(s.phi), cos(s.phi), 0.0f);
    float3 local = rDot * rHat + s.r * thetaDot * thetaHat + s.r * sinTheta * phiDot * phiHat;
    float len = length(local);
    return len > 0.0f ? local / len : rHat;
}

// Proportional to radius, shrinking near the horizon where the momenta
// steepen as one over Delta.
static inline float kerrStepLength(float spin, KerrRayState s, GeodesicSettings g) {
    float aboveHorizon = s.r - kerrOuterHorizon(spin);
    float near = 0.2f * aboveHorizon;
    // Rays with small axial angular momentum turn just short of the pole,
    // where Boyer and Lindquist coordinates pinch; overshooting the turning
    // point lands in the clamped one over sine squared zone, so steps
    // shrink with the distance from the axis.
    float pole = clamp(sin(s.theta) / 0.08f, 0.05f, 1.0f);
    return min(max(min(g.stepFactor * s.r, near) * pole, 0.002f), g.stepMax);
}

#endif
