# 02 step policy away from the disk

2026-08-23, Apple M1 Pro (16 GPU cores), macOS 26.6.1, default preset,
960 by 540 march, after lane 01. Numbers from `gargantua bench --sweep`,
which times the march and reports conserved quantity drift over a 32 by 32
grid of camera rays at the 256 step interactive cap, plus the mean relative
luminance difference of a star free render against the spec policy.

## Hypothesis

The spec policy, h = clamp(0.02 r, 0.02, 0.5), spends its finest work where
it matters least. Inside the disk slab the step must stay near one voxel so
the gather resolves the volume, but a ray farther from the slab than the
step it is about to take samples nothing and only needs geodesic accuracy,
which fourth order Runge Kutta holds at much larger steps.

## Sweep

| Policy | march ms | max drift | p99 drift | exhausted | image diff |
| --- | --- | --- | --- | --- | --- |
| fixed 0.25 | 24.6 | 4.0e-4 | 2.3e-4 | 8 | 1.1e-2 |
| fixed 0.5 | 12.7 | 1.5e-2 | 3.3e-3 | 0 | 2.7e-2 |
| prop 0.02 max 0.5 (spec) | 16.8 | 2.3e-6 | 1.6e-6 | 24 | 0 |
| prop 0.03 max 0.5 | 14.3 | 2.3e-6 | 1.4e-6 | 0 | 1.7e-2 |
| prop 0.04 max 0.5 | 13.6 | 5.0e-6 | 3.2e-6 | 0 | 2.4e-2 |
| prop 0.05 max 1.0 | 8.2 | 1.1e-5 | 6.2e-6 | 0 | 4.8e-2 |
| prop 0.02, empty 0.06 max 1.5 | 12.0 | 3.0e-6 | 1.8e-6 | 8 | 1.5e-3 |
| prop 0.02, empty 0.1 max 3.0 | 11.5 | 1.5e-5 | 1.1e-5 | 12 | 1.2e-3 |
| prop 0.02, empty 0.15 max 4.0 | 11.7 | 7.6e-5 | 4.9e-5 | 16 | 3.1e-4 |
| prop 0.02, empty 0.2 max 6.0 | 12.2 | 2.6e-4 | 1.8e-4 | 18 | 2.2e-4 |
| prop 0.04, empty 0.08 max 2.0 | 9.5 | 1.1e-5 | 4.6e-6 | 0 | 2.4e-2 |
| prop 0.05 max 1.0, empty 0.1 max 3.0 | 6.7 | 2.6e-5 | 1.1e-5 | 0 | 4.8e-2 |
| prop 0.06 max 1.0, empty 0.12 max 3.0 | 6.1 | 5.1e-5 | 2.0e-5 | 0 | 5.9e-2 |

Fixed steps are dominated: either slow (0.25) or two orders of magnitude
over the drift budget (0.5). Every policy that coarsens the step inside the
slab buys speed with 2 to 6 percent of the image, real sampling loss, and
that line is not crossed. Coarsening only the empty legs leaves the image
within 1.5e-3 of the spec policy; the gain saturates near 11.5 ms because
the remaining time is the in slab traversal itself.

One design subtlety: the empty test must compare the distance to the slab
with the step actually about to be taken, not with the policy's maximum,
or raising the maximum shrinks the region that qualifies and the gain
reverses.

## Decision

Interactive: spec sampling inside the slab, empty legs at h = 0.1 r capped
at 3.0. Drift 1.5e-5 against the 1e-4 interactive budget, image within
1.2e-3, exhausted rays halved. Stills: empty legs at h = 0.06 r capped at
1.5, drift 3.9e-6 against the tighter 1e-5 still budget (measured by the
conservation_still golden at the 4096 step cap).

March 16.8 to 10.7 ms in the committed bench, march frame 20.6 to 16.9 ms
together with lane 03. The exhausted ray count in the conservation golden
fell from 48 to 10 of 256.

The spec's third option, a symplectic integrator at larger fixed h, is
deferred: the velocity form in Eddington and Finkelstein coordinates that
the drift monitoring is defined on has a cross term that defeats simple
splitting, and replacing the error gauge together with the integrator would
change what the goldens measure. It stays a candidate behind a lane of its
own.
