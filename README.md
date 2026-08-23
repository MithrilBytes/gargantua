# gargantua

GPU particle accretion disk around a Schwarzschild black hole, rendered
through real gravitational lensing. A native macOS program for Apple
silicon. It opens a window, draws a black hole, and quits when you quit.

It is a visualization with a physics spine, not a research instrument.
Particles orbit and spiral inward under a pseudo Newtonian potential that
reproduces the innermost stable circular orbit; camera rays are integrated
as null geodesics of the Schwarzschild metric, so the lensing, the shadow
and the photon ring are computed rather than painted. Every physical claim
the renderer makes is checked against a double precision CPU oracle by a
test you can run. The line between computed and stylized is drawn below and
never crossed silently.

## What this program can and cannot do to your machine

It can use CPU and GPU cycles, spin fans, warm the chassis, drain a battery
faster, and allocate memory inside a checked budget. That is the complete
list. It runs as an ordinary user process: no administrator rights, no
kernel extensions, no private frameworks, no system settings, no background
agents, no network. The worst realistic failure is a compute kernel that
trips the macOS GPU watchdog, after which the window freezes or the process
dies and the desktop survives.

How that is kept true, in code:

1. Every loop in every shader has a hard iteration cap, named in
   `Sources/Gargantua/Shaders/Constants.h` and checked by a style test.
2. No single command buffer carries more than about 30 ms of GPU work.
3. Every command buffer's completion status is checked. On error the
   program prints one sentence and exits with code 2; nothing is resubmitted.
4. Memory is budgeted before it is allocated: at most 40 percent of the
   device's recommended working set, or 3 GB, whichever is smaller. A
   configuration over budget is refused with one sentence naming the number.
5. Rendering is capped at vsync, 60 Hz by default, 30 by flag.
6. Nothing is written to disk except files you ask for: screenshots, still
   renders and benchmark reports, each to a printed path.
7. First run defaults are modest; the largest preset needs an explicit flag
   and prints a sentence about sustained load first.

## Requirements

| Requirement      | Value                                                   |
| ---------------- | ------------------------------------------------------- |
| Hardware         | Apple silicon Mac, M1 or newer, 8 GB or more            |
| OS               | macOS 14 or newer                                       |
| Build            | Swift 6.0 or newer via Swift Package Manager            |
| Frameworks       | Metal, MetalKit, MetalFX, AppKit, all from Apple        |
| Third party code | none                                                    |

Swift 6.0 is the floor because the tests use Swift Testing, which is what
ships with the Command Line Tools; XCTest does not. Shaders live as `.metal`
source in the repository and are embedded into the binary at build time,
then compiled once per launch by the runtime Metal compiler and kept in
memory. Full Xcode is never needed to build or run.

## Build and run

```bash
swift build -c release
```

```bash
.build/release/gargantua
```

The binary is self contained. `make app` wraps it in a minimal
`Gargantua.app` for the Dock.

```
gargantua                          interactive window, default preset
gargantua --preset small|default|max
gargantua --particles N --volume 96|128|192|256 --seed S
gargantua --strategy march|bake
gargantua --fps-cap 30|60
gargantua --still out.png --width 3840 --height 2160
gargantua bench
gargantua validate                 run the goldens on this machine's GPU
gargantua version
```

Errors are one plain sentence on stderr and a nonzero exit: 2 for an
operational failure, 64 for a usage mistake, 1 from `validate` when a
golden fails.

### Controls

| Input        | Action                                          |
| ------------ | ----------------------------------------------- |
| drag         | orbit camera                                    |
| scroll       | dolly                                           |
| 1 / 2 / 3    | preset small / default / max (max is gated)     |
| space        | pause and resume the simulation                 |
| R            | reseed and restart the disk                     |
| S            | screenshot to ~/Pictures/gargantua/, path printed |
| H            | toggle hud                                      |
| D            | debug view                                      |
| Esc or Cmd-Q | quit                                            |

## Units

Geometrized units, G = c = M = 1. All lengths are in units of the black
hole mass: the horizon sits at r = 2, the photon sphere at 3, the innermost
stable circular orbit at 6, the critical impact parameter at 3 sqrt(3). The
disk is seeded between 6 and 24 and fed from an annulus between 20 and 24.

## Computed and stylized

Computed, and held to the oracle:

- Particle dynamics in the Paczynski and Wiita potential, which places the
  innermost stable orbit at r = 6 and the marginally bound orbit at r = 4.
- The steady state inner edge of the disk, measured from the surface density
  profile and checked by the `isco` golden on both the oracle and the GPU.
- Bitwise determinism of the particle buffer for a fixed seed, checked by
  the `determinism` golden. The simulation pass uses no atomics and no cross
  thread reads; all randomness is a counter based hash of the seed.
- The radial scaling of the thin disk temperature profile and the Planck
  color of each temperature.

Stylized, by design and named as such in `Sources/Oracle/Constants.swift`:

- `T_PEAK_DEFAULT`, the peak disk temperature of 8000 K. A real disk peaks
  in X rays, which a monitor cannot show.
- `ZERO_TORQUE_FLOOR`, a floor on the zero torque factor so gas inside the
  innermost stable orbit stays visible while it plunges.
- `DRAG_ALPHA`, `FEED_VELOCITY_DISPERSION` and `DISK_ASPECT`, which set the
  inflow rate, the orbital dispersion and the disk thickness.
- `SPRITE_RADIUS` and `EXPOSURE_DEFAULT`, which set the look of the image.

Every constant carries its source. Hardware figures carry the date they
were read.

## Checks

CI (GitHub Actions, Apple silicon runner) builds the release binary, runs
`swift test` and scans the repository for em or en dashes on every push.
`swift test` needs no GPU: it runs the oracle tests, the golden definitions
against the oracle, and the repository rules.

GPU validation is local, because a hosted runner's GPU is not dependable
enough to gate a merge on:

```bash
.build/release/gargantua validate
```

A green badge means the code builds and the oracle agrees with itself. It
does not mean the renderer has been validated on a GPU; that is what the
command above is for.

## Development

```bash
make hooks
```

installs the commit hooks that enforce the commit title rule and the dash
rule. `make check` runs the tests, the dash scan and the commit title lint.
`make constants` regenerates the Metal constants header from the Swift
source of truth; a style test fails if the two drift.

The soak harness runs the window for a fixed time, prints a frame timing
summary, writes a screenshot, and quits through the path you choose so all
three exits can be exercised without a person at the keyboard:

```bash
.build/release/gargantua --soak 600 --quit esc
```

Measurements in this repository were taken on an M1 Pro with a 16 core GPU.
Every number in the spec is sized for a base M1 with 8 GPU cores, so GPU
bound figures here are roughly twice as optimistic as that target.

## Repository layout

```
Sources/Gargantua/          host: app, camera, passes, budget checks, validation
Sources/Gargantua/Shaders/  sim.metal, sprites.metal, present.metal, Constants.h
Sources/Oracle/             double precision reference, no Metal imports
Sources/ShaderTypes/        the C header shared by Swift and Metal
Sources/EmbedResourcesTool/ build tool that embeds shaders and goldens
Plugins/EmbedResources/     the SwiftPM build tool plugin that runs it
Tests/OracleTests/          oracle unit tests, analytic checks, goldens
Tests/StyleTests/           repository rule enforcement
goldens/                    expected values and tolerances as data
Makefile                    make app, make check, make constants, make hooks
LICENSE                     MIT
```

## References

1. Paczynski, B. and Wiita, P. J., 1980. Thick accretion disks and
   supercritical luminosities. A&A 88, 23.
2. Shakura, N. I. and Sunyaev, R. A., 1973. Black holes in binary systems.
   A&A 24, 337.
3. Page, D. N. and Thorne, K. S., 1974. Disk accretion onto a black hole.
   Time averaged structure of accretion disk. ApJ 191, 499.
4. Bardeen, J. M., Press, W. H. and Teukolsky, S. A., 1972. Rotating black
   holes: locally nonrotating frames, energy extraction, and scalar
   synchrotron radiation. ApJ 178, 347.
5. Chandrasekhar, S., 1983. The Mathematical Theory of Black Holes. Oxford
   University Press.
6. Luminet, J.-P., 1979. Image of a spherical black hole with thin
   accretion disk. A&A 75, 228.
7. Pringle, J. E., 1981. Accretion discs in astrophysics. ARA&A 19, 137.
8. Hairer, E., Lubich, C. and Wanner, G., 2006. Geometric Numerical
   Integration, 2nd ed. Springer.
9. Jarzynski, M. and Olano, M., 2020. Hash functions for GPU rendering.
   Journal of Computer Graphics Techniques 9(3), 20.
10. Box, G. E. P. and Muller, M. E., 1958. A note on the generation of
    random normal deviates. Annals of Mathematical Statistics 29, 610.
11. Wyman, C., Sloan, P.-P. and Shirley, P., 2013. Simple analytic
    approximations to the CIE XYZ color matching functions. Journal of
    Computer Graphics Techniques 2(2), 1.
12. Tiesinga, E., Mohr, P. J., Newell, D. B. and Taylor, B. N., 2021.
    CODATA recommended values of the fundamental physical constants: 2018.
    Reviews of Modern Physics 93, 025010.
13. IEC 61966-2-1:1999. Default RGB colour space, sRGB.
14. Khronos Group, 2024. PBR Neutral Tone Mapper Specification.
    github.com/KhronosGroup/ToneMapping, read 2026-08-22.
15. James, O., von Tunzelmann, E., Franklin, P. and Thorne, K. S., 2015.
    Gravitational lensing by spinning black holes in astrophysics, and in
    the movie Interstellar. Classical and Quantum Gravity 32, 065001.

## License

MIT. See LICENSE.
