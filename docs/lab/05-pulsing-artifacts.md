# 05 the pulsing particles

2026-08-23, Apple M1 Pro (16 GPU cores), macOS 26.6.1, default preset.
Not a speed lane: a screen recording showed soft dots pulsing around the
disk in the live window, and this note documents the two defects behind
them. The diagnostic was a headless sequence of consecutive native frames
with the simulation advancing, which reproduced both effects without the
upscaler, plus a scan of the resolved volume.

## Defect one: single precision tanh overflows at plunge speeds

The Doppler factor compresses the simulated gas speed below c with
beta = 0.85 tanh(v / 0.85). Pseudo Newtonian plunge speeds near the capture
radius genuinely reach tens of c (the potential is -1 / (r - 2)), and the
fixed point momentum over mass division in the resolve can amplify that
further; the resolved velocity field peaks near 90. Metal's single
precision tanh evaluates exp(2x) and returns nan beyond an argument of
about 44, so voxels holding the fastest gas turned every ray that sampled
them into a nan pixel. The oracle never disagreed because libm's tanh is
exactly 1 there. Downstream, the tone mapper and the temporal upscaler
smear a nan pixel into a drifting blob several pixels wide that lives for
many frames: the most visible of the pulsing dots, and an intermittent
failure of the beaming and jump goldens whenever one landed inside their
192 by 108 render.

The fix caps the tanh argument at 8 (tanh(8 / 0.85) is 1 to eight
decimals), normalizing the velocity direction by the true magnitude. The
first version of the fix normalized by the capped magnitude, which sent a
9 c vector into the Doppler denominator and flipped it negative; the new
unit test at 89 c caught it before it shipped.

## Defect two: nearest voxel binning pops

The splat binned each particle into the voxel containing it. A voxel that
holds one particle, common in the plunge stream, the vertical tails and
the feeding annulus, renders as a voxel sized blob that jumps a whole
voxel the frame its particle crosses a boundary, roughly every ten frames
at default speeds. The temporal upscaler fades each jump, which reads as
dots breathing in and out around the disk.

The deposit is now cloud in cell (Hockney and Eastwood 1988): interactive
frames pick one of the eight corners per particle with the trilinear
weights as probabilities, an unbiased estimate whose noise averages over
particles in dense voxels and over frames under the temporal accumulator,
at the same six atomics per particle; stills and validation deposit into
all eight corners exactly, once. Fixed point conversions round to nearest,
since corner weights can be small enough that truncation would drop whole
quanta. The splat is excluded from the determinism golden, so the per
frame hash is within contract.

## After

Twelve frame sequences show no nan specks and no voxel popping in either
deposit mode; `validate` passes ten of ten in four consecutive runs
(previously intermittent); the splat costs 2.76 ms against 2.81 before the
change; the march frame stays 15.0 ms. What remains at the shadow edge is
single pixel fate flips of near critical rays, real point sampling of a
boundary that compresses the whole sky into a pixel, softened by the
temporal accumulator and left alone.
