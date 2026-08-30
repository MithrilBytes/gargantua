# gargantua

A GPU accretion disk around a black hole, lensed by the black hole
itself. It's a native macOS app for Apple silicon, written in Swift and
Metal, with nothing outside Apple's frameworks underneath.

![A lensed accretion disk around a black hole](docs/gargantua.jpg)

The lensing is the real thing. Camera rays get integrated as null
geodesics of the Schwarzschild metric (or Kerr, if you pass `--spin`), so
the shadow and the photon ring fall out of the math instead of being
drawn in by hand. The particles follow a pseudo Newtonian potential that
puts the innermost stable orbit in the right place. Everything the
renderer claims about physics gets checked twice: a double precision
oracle on the CPU defines the right answers, and `gargantua validate`
makes sure your GPU agrees with them. Some things are deliberately fudged
to look good on a monitor, and every one of those fudges is a named
constant in `Sources/Oracle/Constants.swift` with a citation next to it.

It's an ordinary user process that never touches the network and only
writes files you asked for (screenshots, stills, bench reports). I was
careful with the GPU: work is split into short command buffers so a
misbehaving kernel can't hang your desktop, and memory gets budgeted up
front (at most 40 percent of the device's recommended working set, capped
at 3 GB) before anything is allocated. If a configuration would blow the
budget, the app says so and quits rather than trying.

## Requirements

Any Apple silicon Mac (M1 or newer, 8 GB or more) running macOS 14 or
later, plus Swift 6.0. The Command Line Tools are all you need, since the
shaders ship as source and get compiled when the app launches. You never
have to open Xcode.

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

When something goes wrong you get one line on stderr and a nonzero exit:
2 for an operational failure, 64 for a usage mistake, and 1 from
`validate` when a golden fails.

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

1. **sim** moves every particle a step through the Paczynski and Wiita
   potential with semi implicit Euler, plus a little drag to drive the
   slow spiral inward. Particles that fall in or fly away respawn in a
   feeding annulus. The kernel avoids atomics entirely, which is why a
   fixed seed reproduces a run bit for bit.
2. **splat** gathers the particles into a 3D emission and velocity field
   using fixed point atomics, then resolves that into half precision
   textures.
3. **march** traces one null geodesic per ray with fourth order Runge
   Kutta. While a ray is inside the disk slab it samples the volume,
   scales the emission by the redshift factor cubed (gravitational and
   Doppler together), and composites front to back. Once a ray is outside
   r = 30 there's nothing left to sample, so it crosses the empty stretch
   analytically using precomputed deflection tables
   (`docs/lab/01-sweep-tables.md`). Rays that escape to infinity pick up
   a procedural starfield, and rays that fall in stay black.
4. **present** upscales the march resolution to the window with MetalFX
   temporal upscaling and runs the result through the Khronos PBR Neutral
   tone curve.

`--strategy bake` takes a different route: it integrates each ray once
per camera position and stores the sample points (about 400 MB worth at
960 by 540), after which a frame is just texture walks. Move the camera
and it falls back to marching until you stop. A ray that needs more than
96 stored samples loses its tail, and `bench` will tell you how many did.
`gargantua bench` times both strategies so you can compare on your own
machine.

Everything is in geometrized units, G = c = M = 1, which puts the horizon
at r = 2, the photon sphere at 3, the innermost stable circular orbit at
6, and the critical impact parameter at 3 sqrt(3). The disk gets fed from
an annulus between 20 and 24.

## Validation

The same golden files keep both sides honest: `swift test` checks the
oracle against them on any machine, and `gargantua validate` checks your
GPU against them. They live as plain data in `goldens/`:

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

The splat pass is left out of the determinism golden because atomic
accumulation order varies from run to run. As for the fudges: the disk
peaks at 8000 K because a real one peaks in X rays your monitor can't
show, the beaming velocity gets smoothly compressed below c, and the
exposure and opacity constants are pure taste. Each one is named and
sourced in `Sources/Oracle/Constants.swift`.

## Performance

On my M1 Pro (16 GPU cores) the default preset marches a frame in about
15 ms and walks a baked one in about 6.5 ms. Dated bench reports live in
`bench/results/`, and the notes in `docs/lab/` walk through each
optimization with the measurements that motivated it.

## Known limits

The GPU only does fp32. Between unit scaling, horizon regular coordinates
and the monitored conserved quantities, a 4096 step ray drifts by about
2.3e-6 relative on my hardware, and since the double precision oracle
drifts 2e-7 under the same step policy, the step policy is the real
accuracy floor rather than the arithmetic. In the interactive window,
rays passing close to the hole hit the 256 step cap (about a fifth of the
default view). Their fate is still decided exactly, and the hud counts
them if you're curious.

The disk is a cloud of particles with drag, so you won't find pressure,
magnetic fields or real turbulence in here. It makes a convincing picture
of an accretion disk without being a serious simulation of one. Lensing
is also applied to the volume as a whole rather than to individual
particles, which means a doubled image comes from a ray crossing the
volume twice. That's correct in aggregate and slightly wrong per
particle.

Passing `--spin` switches the rays to Kerr null geodesics in Boyer and
Lindquist coordinates while the disk keeps its pseudo Newtonian dynamics,
so frame dragging reaches the image entirely through the lensing. The
deflection table shortcut only exists for Schwarzschild, which drops
interactive spin to around 8 fps on an M1 Pro, so spin is best enjoyed
through stills. You may also spot a faint seam on the polar axis where
the coordinates pinch.

MetalFX runs with zero motion vectors, which sounds wrong but measured
better against ground truth than every reprojection variant I tried
(`docs/lab/06-pulsing-round-two.md`). Fast camera moves can still ghost a
little, and `--no-upscale` gives you a clean native render for captures.
On fanless machines the max preset will throttle after a few minutes.
Nothing breaks when that happens, the clock just drops and the fps
counter shows it.

## Development

```bash
make hooks
```

sets up the repo's commit hooks. `make check` runs the tests plus the
commit lint. If your Mac only has the Command Line Tools, run tests
through `make test`: those installs put Swift Testing somewhere plain
`swift test` doesn't look, and the Makefile knows where. `make constants`
regenerates the Metal constants header from the Swift source of truth.

CI builds the release binary and runs the CPU side tests on every push.
GPU validation stays local since hosted runners' GPUs aren't dependable
enough to gate a merge on. There's also a soak harness that runs the
window unattended, prints a timing summary, grabs a screenshot and exits
through whichever path you pick:

```bash
.build/release/gargantua --soak 600 --quit esc
```

## References

Every constant in `Sources/Oracle/Constants.swift` carries its own
citation. The big ones:

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
