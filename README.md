# gargantua

A GPU particle accretion disk around a black hole, rendered through real
gravitational lensing. Native macOS on Apple silicon, written in Swift and
Metal with no third party dependencies.

![A lensed accretion disk around a black hole](docs/gargantua.jpg)

The physics is honest where it counts. Particles orbit and spiral inward
in a pseudo Newtonian potential with the correct innermost stable orbit,
and camera rays are integrated as null geodesics of the Schwarzschild
metric (Kerr with `--spin`), so the shadow, the photon ring and the
lensing are computed rather than painted. A double precision CPU oracle
checks the renderer's claims, and `gargantua validate` reruns those checks
on your GPU. Where the image is stylized instead of computed, the constant
responsible is named in `Sources/Oracle/Constants.swift` with a citation.

It runs as an ordinary user process: no network, no admin rights, no
background agents, and it writes only files you ask for (screenshots,
stills, bench reports). GPU work is split into short command buffers so a
bad kernel cannot hang the desktop, and memory is budgeted before it is
allocated, at most 40 percent of the device's recommended working set or
3 GB, whichever is smaller. Configurations over budget are refused.

## Requirements

An Apple silicon Mac (M1 or newer, 8 GB or more) on macOS 14 or newer,
with Swift 6.0 or newer. The Command Line Tools are enough; full Xcode is
not needed. Shaders ship as source and are compiled at launch.

## Build and run

```bash
swift build -c release
```

```bash
.build/release/gargantua
```

`make app` wraps the binary in a minimal `Gargantua.app` for the Dock.

```
gargantua                          interactive window, default preset
gargantua --preset small|default|max
gargantua --particles N --volume 96|128|192|256 --seed S
gargantua --strategy march|bake
gargantua --spin 0.9               Kerr rays, march strategy only
gargantua --fps-cap 30|60
gargantua --no-upscale             present the march resolution directly
gargantua --still out.png --width 3840 --height 2160
gargantua --still f.png --sequence 240   also write seq-NNN.png frames beside the still
gargantua bench                    time the passes, write bench/results/<date>.json
gargantua validate                 run the goldens on this machine's GPU
```

Errors go to stderr with a nonzero exit: 2 for an operational failure, 64
for a usage mistake, 1 from `validate` when a golden fails.

| Input        | Action                                          |
| ------------ | ----------------------------------------------- |
| drag         | orbit camera                                    |
| scroll       | dolly                                           |
| 1 / 2 / 3    | preset small / default / max (max needs `--preset max` at launch) |
| space        | pause and resume                                |
| R            | reseed and restart the disk                     |
| S            | screenshot to ~/Pictures/gargantua/             |
| H            | toggle hud                                      |
| D            | debug view: conserved quantity drift, shaded by step count |
| Esc or Cmd-Q | quit                                            |

| Preset  | Particles | Volume | March resolution |
| ------- | --------- | ------ | ---------------- |
| small   | 250k      | 96^3   | 640 by 360       |
| default | 1M        | 128^3  | 960 by 540       |
| max     | 4M        | 256^3  | 960 by 540       |

## How it works

Four passes per frame:

1. **sim** steps every particle with semi implicit Euler in the Paczynski
   and Wiita potential plus a small drag that drives the inflow. Captured
   and escaped particles respawn in a feeding annulus. No atomics, so a
   fixed seed reproduces the run bit for bit.
2. **splat** bins particles into a 3D emission and velocity field with
   fixed point atomics, then resolves to half precision textures.
3. **march** traces one null geodesic per ray with fourth order Runge
   Kutta, samples the volume inside the disk slab, shifts the emission by
   the redshift factor cubed (gravitational plus Doppler), and composites
   front to back. Outside r = 30 there is nothing to sample, so rays cross
   the empty region analytically using precomputed deflection tables
   (`docs/lab/01-sweep-tables.md`). Escaped rays shade a procedural
   starfield; captured rays are black.
4. **present** upscales the march resolution to the window with MetalFX
   temporal upscaling and tone maps with the Khronos PBR Neutral curve.

`--strategy bake` integrates each ray once per camera position and stores
its sample points (about 400 MB at 960 by 540); a frame is then only
texture walks, and moving the camera falls back to the march. Rays that
need more than 96 stored samples lose their tail; `bench` reports how
many. `gargantua bench` times both strategies.

Units are geometrized, G = c = M = 1. The horizon sits at r = 2, the
photon sphere at 3, the innermost stable circular orbit at 6, the critical
impact parameter at 3 sqrt(3), and the disk is fed from an annulus between
20 and 24.

## Validation

`gargantua validate` holds the GPU to the same golden files that
`swift test` holds the oracle to. The goldens are data in `goldens/`:

| Golden                   | Claim                                                   | Bar          |
| ------------------------ | ------------------------------------------------------- | ------------ |
| isco                     | steady state surface density inner edge sits at r = 6   | 5 percent    |
| determinism              | particle buffer checksum after 1000 steps, fixed seed   | bitwise      |
| shadow                   | bisected capture boundary sits at b_c = 5.196           | 1 percent    |
| deflection               | bending at b = 1000 matches 4/b                         | 0.5 percent  |
| conservation_interactive | per ray E and L relative drift, 256 step interactive    | under 1e-4   |
| conservation_still       | per ray E and L relative drift, 4096 step still         | under 1e-5   |
| parity                   | GPU geodesic endpoints vs oracle, 64 sampled rays       | under 1e-3   |
| beaming                  | approaching to receding brightness ratio vs oracle render | 10 percent |
| sky                      | sweep table sky directions match the oracle far out     | under 1e-3 rad |
| jump                     | image with the sphere jump matches full integration     | 1 percent    |
| shadow_kerr              | shadow asymmetry at spin 0.9 matches the oracle         | 2 percent    |

The splat pass sits outside the determinism golden because atomic
accumulation order is not deterministic. The deliberate departures from
physics (a peak temperature of 8000 K instead of X rays, a smooth velocity
compression below c for the beaming, the exposure and opacity constants)
are all named and sourced in `Sources/Oracle/Constants.swift`.

## Performance

On an M1 Pro with a 16 core GPU the default preset marches a frame in
about 15 ms and walks a baked one in about 6.5 ms. Dated bench reports are
committed in `bench/results/` and the optimization notes, with the
measurements that motivated each change, in `docs/lab/`.

## Known limits

The GPU is fp32. With unit scaling, horizon regular coordinates and
monitored conserved quantities, a 4096 step ray drifts by 2.3e-6 relative
on this hardware, while the double precision oracle under the same step
policy drifts 2e-7, so the step policy sets the accuracy floor, not the
precision. Interactive rays passing near the hole hit the 256 step cap
(about a fifth of the default view); their fate is still decided exactly,
and the hud shows the count.

The disk is particles with drag, not a fluid. No pressure, no magnetic
fields, no turbulence. It looks like an accretion disk; it is not a
simulation of one. Lensing applies to the volume and the background, not
particle by particle, so double images come from a ray crossing the volume
twice, which is correct in aggregate.

With `--spin` the rays are Kerr null geodesics in Boyer and Lindquist
coordinates while the disk stays pseudo Newtonian, so frame dragging
reaches the image through the lensing alone. The deflection table shortcut
is Schwarzschild only, so interactive spin runs near 8 fps on an M1 Pro;
stills are the intended way to look at spin. A faint seam can appear on
the polar axis where the coordinates pinch.

MetalFX runs with zero motion vectors, which measured better against
ground truth than every reprojection variant tried
(`docs/lab/06-pulsing-round-two.md`). Fast camera moves can still ghost;
`--no-upscale` renders natively for clean captures. Fanless machines
throttle under the max preset; the program stays correct and smooth at
whatever clock the OS grants.

## Development

```bash
make hooks
```

installs the commit hooks, which keep commit titles in the house format.
`make check` runs the tests and the commit lint. On a Mac with only the Command Line Tools, test through
`make test`: those installs put Swift Testing where plain `swift test`
does not look. `make constants` regenerates the Metal constants header
from the Swift source of truth.

CI builds the release binary and runs the CPU side tests on every push.
GPU validation is local, because a hosted runner's GPU is not dependable
enough to gate a merge on. The soak harness runs the window unattended,
prints a timing summary, takes a screenshot and exits through a chosen
path:

```bash
.build/release/gargantua --soak 600 --quit esc
```

## References

Every constant carries its own citation in
`Sources/Oracle/Constants.swift`; the core references are:

1. Paczynski, B. and Wiita, P. J., 1980. Thick accretion disks and
   supercritical luminosities. A&A 88, 23.
2. Shakura, N. I. and Sunyaev, R. A., 1973. Black holes in binary systems.
   A&A 24, 337.
3. Bardeen, J. M., Press, W. H. and Teukolsky, S. A., 1972. Rotating black
   holes: locally nonrotating frames, energy extraction, and scalar
   synchrotron radiation. ApJ 178, 347.
4. Chandrasekhar, S., 1983. The Mathematical Theory of Black Holes. Oxford
   University Press.
5. Luminet, J.-P., 1979. Image of a spherical black hole with thin
   accretion disk. A&A 75, 228.
6. James, O., von Tunzelmann, E., Franklin, P. and Thorne, K. S., 2015.
   Gravitational lensing by spinning black holes in astrophysics, and in
   the movie Interstellar. Classical and Quantum Gravity 32, 065001.

## License

MIT. See LICENSE.
