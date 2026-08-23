# 03 threadgroup shape for the ray kernels

2026-08-23, Apple M1 Pro (16 GPU cores), macOS 26.6.1, default preset,
960 by 540 march at the spec step policy, from `gargantua bench --sweep`.

## Hypothesis

One thread per ray with 32 by 4 threadgroups was a guess. Rays that share a
simdgroup finish together only if they take similar step counts, and step
count varies most horizontally across the image (sky, disk, shadow), so a
squarer tile should put more similar rays in one simdgroup.

## Sweep

| Threadgroup | march ms |
| ----------- | -------- |
| 32 by 4     | 17.0     |
| 64 by 2     | 17.0     |
| 128 by 2    | 17.0     |
| 64 by 4     | 17.0     |
| 32 by 8     | 17.2     |
| 16 by 4     | 15.9     |
| 16 by 8     | 15.7     |
| 16 by 16    | 15.9     |
| 8 by 4      | 15.5     |
| 8 by 16     | 15.4     |
| 4 by 16     | 15.3     |
| 4 by 8      | 15.5     |
| 8 by 8      | 15.1     |

## Decision

8 by 8, about 10 percent off the march against 32 by 4, applied to the
march, probe, bake and walk kernels, which share the one ray per thread
structure. The shape is a named constant. Wider than 32 threads per row
gains nothing: an Apple simdgroup is 32 lanes, and a 32 wide row already
spans a full simdgroup of maximally dissimilar rays.

Volkov 2010 (better performance at lower occupancy) suggests the next
probe: spilling and occupancy for the march kernel's 6 variable ray state,
which belongs to the register pressure lane if one opens.
