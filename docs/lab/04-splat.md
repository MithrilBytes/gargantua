# 04 splat without a hot resolve

2026-08-23, Apple M1 Pro (16 GPU cores), macOS 26.6.1, default preset,
1M particles into a 128 cubed volume. Phase timings from
`gargantua bench --sweep`.

## Hypothesis

The splat pass stood at 4.6 ms against a 2 ms budget. It had two phases in
one encoder: a bin over particles (seven atomic adds each) and a resolve
over voxels (seven atomic exchanges each, doubling as the zeroing step).
The resolve's atomics buy nothing: dispatches in one encoder are ordered,
so plain loads see the finished sums, and a blit fill zeroes buffers at
memory speed. The bin can also lose one atomic: summing energy and energy
weighted temperature, then tinting at resolve from the mean temperature,
replaces three tinted channel sums. Within one voxel of the default volume
the temperature spread is a few hundred kelvin, far below a visible tint
difference on a 4000 to 8000 K disk.

## Measurement

| Phase        | Before (ms) | After (ms) |
| ------------ | ----------- | ---------- |
| bin          | 2.57        | 2.18       |
| resolve      | 2.02        | 0.36       |
| fill         |             | about 0.25 |
| splat total  | 4.59        | 2.81       |

All ten goldens pass unchanged, including beaming, which renders the oracle
from the resolved volume and would catch a tint regression. The march frame
fell from 16.9 to 15.0 ms, under one 60 Hz interval for the first time; a
15 second soak holds 58.6 fps with p50 at 16.67 ms and no command buffer
errors.

## Remaining gap

The bin's 2.18 ms is atomic bound: one million particles issue six
serialized read modify writes each, and the hot inner disk voxels contend.
On a base M1 the 2 ms budget corresponds to about 1 ms here, so the pass is
still about two of those budgets over on that hardware. Two candidates are
left on the table, in order of honesty: amortizing the splat across two
frames (the disk moves a tenth of a voxel per frame, so a 30 Hz volume
under 60 Hz rays would not show; it does change the four passes per frame
contract, so it needs its own writeup), and sorting particles by voxel so
simdgroups can pre reduce before touching memory.
