# gargantua

Accretion disk simulation around a black hole with gravitational lensing.
Native macOS on Apple silicon, written in Swift and Metal, no third party
dependencies.

![A lensed accretion disk around a black hole](docs/gargantua.jpg)

Camera rays are integrated as null geodesics of the Schwarzschild metric,
or Kerr with `--spin`. Particles follow a Paczynski and Wiita potential.
A double precision CPU oracle backs the renderer, and `gargantua
validate` compares the GPU against it. Stylized constants are named and
cited in `Sources/Oracle/Constants.swift`.

## Requirements

Apple silicon Mac with 8 GB or more, macOS 14 or later, Swift 6.0 or
later. Builds with the Command Line Tools; Xcode is not required. Shaders
compile at launch.

## Build and run

```bash
swift build -c release
```

```bash
.build/release/gargantua
```

`make app` produces `Gargantua.app`.

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

Exit codes: 2 operational failure, 64 usage error, 1 validation failure.

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

1. **sim**: semi implicit Euler in the Paczynski and Wiita potential with
   a small drag. Captured and escaped particles respawn in a feeding
   annulus. A fixed seed reproduces a run bit for bit.
2. **splat**: particles are deposited into a 3D emission and velocity
   field with fixed point atomics and resolved to half precision
   textures.
3. **march**: one null geodesic per ray, integrated with fourth order
   Runge Kutta. Rays sample the volume inside the disk slab, scale
   emission by the redshift factor cubed, and composite front to back.
   Outside r = 30 rays follow the analytic solution with bending from
   precomputed deflection tables (`docs/lab/01-sweep-tables.md`).
   Escaping rays shade a procedural starfield; captured rays render
   black.
4. **present**: MetalFX temporal upscaling to the window resolution, then
   the Khronos PBR Neutral tone curve.

`--strategy bake` integrates each ray once per camera position and stores
up to 96 sample positions per ray, about 400 MB at 960 by 540. Frames
then read the stored samples; camera motion falls back to the march. Rays
over the sample cap are truncated, and `bench` reports the count.

Units are geometrized, G = c = M = 1: horizon at r = 2, photon sphere at
3, innermost stable circular orbit at 6, critical impact parameter
3 sqrt(3). The disk is fed from an annulus between 20 and 24.

## Validation

`swift test` checks the oracle against the goldens in `goldens/`;
`gargantua validate` checks the GPU against the same files.

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

The determinism golden covers the sim pass only.

## Performance

On an M1 Pro with a 16 core GPU, the default preset marches a frame in
about 15 ms; a baked frame walks in about 6.5 ms. Bench reports are in
`bench/results/`, optimization notes in `docs/lab/`.

## Known limits

GPU integration is fp32. A 4096 step ray drifts about 2.3e-6 relative;
the double precision oracle drifts 2e-7 under the same step policy.
Interactive rays passing near the hole hit the 256 step cap, about a
fifth of the default view; the hud shows the count.

The disk model is particles with drag. Pressure, magnetic fields and
turbulence are absent. Lensing applies to the volume rather than to
individual particles.

With `--spin`, rays are Kerr null geodesics in Boyer and Lindquist
coordinates; disk dynamics remain pseudo Newtonian. The deflection tables
are Schwarzschild only, and interactive spin runs near 8 fps on an
M1 Pro. A faint seam can appear on the polar axis.

MetalFX runs with zero motion vectors (`docs/lab/06-pulsing-round-two.md`).
Fast camera moves can ghost; `--no-upscale` renders natively. Fanless
machines throttle under the max preset.

Memory is capped at 40 percent of the device's recommended working set or
3 GB, whichever is smaller; configurations over the cap are refused.

## Development

`make hooks` sets up the commit hooks. `make check` runs the tests and
the commit lint. On Command Line Tools only installs, run `make test`,
which adds the search paths Swift Testing needs. `make constants`
regenerates the Metal constants header from the Swift source of truth.

CI builds the release binary and runs the CPU side tests on every push.
GPU validation is local:

```bash
.build/release/gargantua validate
```

`--soak` runs the window for a fixed time, prints a timing summary,
writes a screenshot and exits through the path given by `--quit`:

```bash
.build/release/gargantua --soak 600 --quit esc
```

## References

Constants in `Sources/Oracle/Constants.swift` carry their own citations.

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
