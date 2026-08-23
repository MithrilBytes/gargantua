# 01 sweep tables outside the integration sphere

2026-08-23, Apple M1 Pro (16 GPU cores), macOS 26.6.1, default preset,
960 by 540 march, 1920 by 1080 output. Baseline is the M4 renderer at
`bench/results/2026-08-23-032205.json`.

## Hypothesis

Most steps of a default view ray are spent outside the disk, where there
is nothing to sample: from the camera at r = 52 in to the volume cube, and
from the cube out to the escape radius at 60. In Schwarzschild the bending
along those legs depends on the impact parameter alone, so it can be looked
up instead of integrated.

## Method

An integration sphere of radius 30 (the volume half extent) bounds the
march. A ray launched outside it jumps to the sphere along the exact
ingoing solution: its azimuth advances by S(30, b) minus S(R, b), where

    S(R, b) = integral from u = 0 to 1 / R of b du / sqrt(1 - b^2 u^2 (1 - 2u))

is the sweep of an escaping ray from radius R to infinity, and its radial
and azimuthal velocities at the sphere follow from the conserved energy and
angular momentum. It is then integrated as before and, on leaving the
sphere outward, its direction at infinity is its azimuth plus S(30, b).
Rays whose periapsis lies outside r = 29 never enter; their whole turn,
2 (S(r_p, b) minus S(R, b)) plus S(R, b), comes from a third table. Rays
that start outward take S(R, b) directly.

The three tables hold 1024 entries each, sampled in a coordinate that
resolves the square root behaviour of S near the tangential limit, and the
two camera dependent ones are recomputed on the CPU when the camera radius
changes, about a millisecond. The oracle computes them with a midpoint rule
after the substitution u = uMax sin^2(theta), which makes the turning point
integrand finite; the oracle tests check the tables against the RK4
integrator (1e-5 rad on a full turn) and the Binet orbit equation.

Two goldens hold the GPU to it: `jump` compares a disk only image with and
without the jump, and `sky` compares asymptotic directions with the oracle
integrated out to r = 1e6.

## Measurement

| Pass or frame | Before (ms) | After (ms) | Change |
| ------------- | ----------- | ---------- | ------ |
| march         | 31.8        | 17.0       | 46 percent less |
| march frame   | 37.8        | 24.1       | 36 percent less |
| bake          | 33.9        | 17.4       | 49 percent less |
| walk          | 2.4         | 2.0        | |

After is `bench/results/2026-08-23-040008.json`. Over the session the march
measured between 14.8 and 17.0 ms on this lane; the GPU clock wanders with
temperature, so only files taken minutes apart on the same machine are
compared. The march frame now sits between two vsync intervals, so the
interactive window paces at 30 fps until another lane brings it under
16.7 ms.

Accuracy moved the right way: `jump` reports a 1.2e-3 mean relative
luminance difference from the full integration, and `sky` a worst case of
6.9e-4 rad, better than before, since the full integration stopped at
r = 60 and ignored the bending beyond it.

## Lessons

1. Simpson's rule evaluated the turning point endpoint as 0 / 0 = 0, an
   error of one endpoint weight that shrank linearly with the interval
   count and looked like a resolution problem. The midpoint rule never
   touches an endpoint.
2. The turn of a ray launched inward from R is 2 (S(r_p) minus S(R)), not
   2 S(r_p) minus S(R); the Binet equation integrated in phi was the third
   opinion that settled which of two disagreeing methods was right.
3. Rays leave the sphere with up to half a step of overshoot, and the
   sweep table is exact only from the sphere: b / r^2 per unit of overshoot
   is up to 1e-2 rad at b near 29. The exiting step is redone with the
   fraction that lands on the sphere.
4. Linear texture sampling puts entry i at (i + 0.5) / N; a table indexed
   at i / (N - 1) is off by up to half a texel without the remap.

## Next

About 7 percent of rays still reach the 256 step cap, all of them near the
hole; the step policy inside the sphere is the next lane. The splat pass at
4.4 to 4.8 ms stands against a 2 ms budget.
