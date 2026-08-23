# 06 the pulsing particles, round two

2026-08-23, Apple M1 Pro (16 GPU cores), macOS 26.6.1, default preset. A
wider look after 05: pops and specks were fewer but not gone. Three
findings, one of them the actual culprit, one a genuine strobe source, and
one a measured negative result.

## The culprit: particles tunneling through the capture sphere

The capture check ran on the position after each substep. Near the pole of
the potential a plunging particle takes a gravity kick of order
1 / (r - 2)^2, and one dt = 0.1 substep can then carry it clean across the
capture sphere: never inside r = 2.02 at check time, slingshotted to
coordinate speeds far beyond the free fall ceiling of 10 (the resolved
velocity field showed 89), and off through the disk as a luminous bullet.
Every crossing was one bright oval flashing into a frame and out two
frames later; these were the blobs that survived the lane 05 fixes, and
their impossible speeds were also what pushed tanh into overflow there.

Capture now tests the swept segment: the closest approach of the substep's
chord to the origin, plus a speed limit at 12, above anything a bound
orbit can reach (a constant with the derivation in its note). Both mirrored
in the oracle as `ParticleDynamics.removed`, with a unit test that runs a
step straight through the origin region. The flash in the reference
sequence (same seed, same frame) is gone.

## A real strobe source: beaming lone particles

g^3 spans three orders of magnitude between approaching and receding gas at
the speed ceiling. A voxel holding one plunging particle carries that
particle's velocity as its bulk velocity, so its blob strobes as the
velocity sweeps past the camera direction. Continuum gas does not do this;
one particle is not a continuum. Doppler beaming now blends in with
min(density / BEAMING_DENSITY_FLOOR, 1), gravitational redshift always
applies, and the floor sits at about four particles per default voxel. The
dense disk is untouched: the beaming golden reads 3.202 against 3.202
after mirroring the floor in the oracle.

## A negative result: motion vectors for the upscaler

The residual shimmer under MetalFX suggested feeding it real motion
vectors, from camera reprojection and from the opacity weighted gas
velocity along each ray. Ground truth said no: rendering every frame of a
camera orbit natively at the output resolution and scoring the upscaled
frame against it, zero motion vectors beat every variant tried, at two
orbit speeds.

| Vectors, orbit 0.01 rad per frame | error vs truth |
| --------------------------------- | -------------- |
| zero                              | 1.102          |
| camera reprojection only          | 1.127          |
| camera plus gas, either sign      | 1.126 to 1.130 |
| rotation for sky, zero for gas    | 1.130          |

At 0.03 rad per frame: zero 1.052 against 1.074 for the best variant. The
reading: almost every pixel mixes lensed gas, lensed sky and stars, which
move in different directions that no single straight line vector
describes, and stars given finite depth acquire parallax they do not have.
The reprojection machinery is removed and the motion texture is zero;
MetalFX treats the jittered stream as accumulation, which measured best.

Two instrument lessons for the next hunt: counting changed pixels between
consecutive upscaled frames rewards ghosting, because blur suppresses
change, and a temporal spike count does too; only a per frame ground truth
comparison ranked variants honestly.

## After

Same seed sequences are clean in both deposit modes, ten of ten goldens
pass, 50 tests pass, and the bench frame is unchanged within noise. The
photon ring's single pixel shimmer remains, as documented in 05.
