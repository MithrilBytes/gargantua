# Lane 07: Kerr rays

## Question

Can the march strategy carry a spinning hole with the same evidence
standard as the Schwarzschild path: an oracle, goldens, and a GPU that
matches it?

## What was built

Null geodesics of the Kerr metric in Boyer and Lindquist coordinates,
integrated with RK4 from a separable Hamiltonian. Energy and axial
angular momentum enter as parameters of the potentials, the Carter
constant and the null residual ride along as drift gauges. Rays launch
from a static observer tetrad. The oracle lives in `Sources/Oracle/`
with the shadow edge found by bisecting Bardeen's critical impact
parameters; the kernel mirror lives in `Shaders/Kerr.h` and the march
kernel branches on spin.

## Acceptance

The shadow of a spin 0.9 hole is asymmetric: the prograde edge sits
closer to the axis than the retrograde edge. The `shadow_kerr` golden
bisects both edges on the GPU at spin 0.9 and compares the asymmetry
ratio against the oracle. Result: gpu 2.4020 vs oracle 2.4020, ratio
1.0000, inside the 2 percent gate. Bardeen's closed forms pin the
critical impact parameters to one part in a thousand in the oracle
tests, so both sides are held to the same analytic reference.

Reference: Bardeen, in Black Holes, ed. DeWitt and DeWitt, 1973, the
critical xi and eta of the spherical photon orbits.

## The polar seam

First spin stills showed a dotted vertical line through the image
center. The camera looks at the origin, so the spin axis projects to
that column; rays with small axial angular momentum have a theta
turning point just short of the pole, and a fixed step policy
overshoots it into the region where one over sine squared is clamped.
The fix scales the step length with the sine of theta near the axis,
in the kernel and the oracle alike. The heavy speckle is gone; a
faint hairline remains at the exact axis, the usual price of Boyer
and Lindquist coordinates. Kerr and Schild coordinates would remove
it and are noted as future work, not attempted here.

## Cost

Spin disables the sweep table jump, which is a Schwarzschild identity,
so every ray integrates from the camera. Interactive spin runs near
8 fps on an M1 Pro at the default preset; stills take under a second
at 1280 by 720. The bake strategy refuses spin loudly rather than
producing a wrong table.
