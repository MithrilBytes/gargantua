// Generated from Sources/Oracle/Constants.swift. Do not edit by hand.
// Regenerate with: make constants
#ifndef GARGANTUA_CONSTANTS_H
#define GARGANTUA_CONSTANTS_H

// Event horizon at r = 2M in units where G = c = M = 1.
// Source: Schwarzschild, K., 1916. Sitzungsberichte der Koniglich Preussischen Akademie der Wissenschaften, 189. Chandrasekhar, S., 1983. The Mathematical Theory of Black Holes. Oxford University Press, ch. 3.
#define R_SCHWARZSCHILD (2.0f)

// Unstable circular photon orbit at r = 3M.
// Source: Chandrasekhar, S., 1983. The Mathematical Theory of Black Holes. Oxford University Press, ch. 3.
#define R_PHOTON_SPHERE (3.0f)

// Innermost stable circular orbit for a non rotating hole, r = 6M.
// Source: Bardeen, J. M., Press, W. H. and Teukolsky, S. A., 1972. Rotating black holes: locally nonrotating frames, energy extraction, and scalar synchrotron radiation. ApJ 178, 347. Chandrasekhar, S., 1983. The Mathematical Theory of Black Holes. Oxford University Press, ch. 3.
#define R_ISCO (6.0f)

// Marginally bound circular orbit at r = 4M; also reproduced by the Paczynski and Wiita potential.
// Source: Bardeen, J. M., Press, W. H. and Teukolsky, S. A., 1972. Rotating black holes: locally nonrotating frames, energy extraction, and scalar synchrotron radiation. ApJ 178, 347.
#define R_MARGINALLY_BOUND (4.0f)

// Critical impact parameter 3 sqrt(3) M separating captured from escaping null geodesics; the shadow radius.
// Source: Chandrasekhar, S., 1983. The Mathematical Theory of Black Holes. Oxford University Press, ch. 3. Luminet, J.-P., 1979. Image of a spherical black hole with thin accretion disk. A&A 75, 228.
#define B_CRITICAL (5.196152422706632f)

// Weak field light deflection is 4M / b for impact parameter b much larger than M.
// Source: Einstein, A., 1916. Die Grundlage der allgemeinen Relativitatstheorie. Annalen der Physik 49, 769. Weinberg, S., 1972. Gravitation and Cosmology. Wiley, ch. 8.
#define WEAK_DEFLECTION_COEFFICIENT (4.0f)

// Rays and particles terminate here, one percent above the horizon, so single precision arithmetic never evaluates the metric at r = 2.
// Source: gargantua design choice, see note.
#define R_CAPTURE (2.02f)

// Rays and particles beyond this radius are treated as escaped.
// Source: gargantua design choice, see note.
#define R_ESCAPE (60.0f)

// Outer edge of the seeded disk and of the feeding annulus.
// Source: gargantua design choice, see note.
#define R_DISK_OUTER (24.0f)

// Inner edge of the annulus where captured and escaped particles respawn.
// Source: gargantua design choice, see note.
#define R_FEED_INNER (20.0f)

// Rays sample the volume only within this height of the disk plane. Seeding puts gas within 0.05 r Gaussian of the plane, so at the outer edge five sigma is 6; vertical oscillation amplitudes are conserved under gravity and shrink under drag.
// Source: gargantua design choice, see note.
#define DISK_SLAB_HALF_HEIGHT (6.0f)

// Half width of the cube the splat pass bins particles into, centered on the hole.
// Source: gargantua design choice, see note.
#define VOLUME_HALF_EXTENT (30.0f)

// Fixed timestep per substep in code units. The innermost stable orbit has angular frequency 1 / sqrt(96) in the Paczynski and Wiita potential, so dt times omega is 0.0102, far inside the stability bound of 2 for symplectic Euler on harmonic motion.
// Source: Hairer, E., Lubich, C. and Wanner, G., 2006. Geometric Numerical Integration, 2nd ed. Springer, ch. I.
#define SIM_DT (0.1f)

// Substeps per rendered frame.
// Source: gargantua design choice, see note.
#define SIM_SUBSTEPS (2u)

// Velocity space drag rate as a fraction of the local circular angular frequency; stands in for viscosity and drives the inward spiral.
// Source: gargantua design choice, see note.
#define DRAG_ALPHA (0.003f)

// Gaussian velocity dispersion per component as a fraction of the local circular speed, applied at seeding and respawn.
// Source: gargantua design choice, see note.
#define FEED_VELOCITY_DISPERSION (0.02f)

// Vertical Gaussian scale height as a fraction of radius; thin disk regime h / r much smaller than 1.
// Source: Pringle, J. E., 1981. Accretion discs in astrophysics. ARA&A 19, 137.
#define DISK_ASPECT (0.05f)

// Stylized. Peak of the thin disk temperature profile in kelvin; real disks peak far hotter than a monitor can show.
// Source: gargantua design choice, see note.
#define T_PEAK_DEFAULT (8000.0f)

// Stylized. Floor on the zero torque factor 1 - sqrt(r_isco / r) so gas inside the innermost stable orbit keeps a finite, cooler temperature instead of vanishing.
// Source: gargantua design choice, see note.
#define ZERO_TORQUE_FLOOR (0.01f)

// Lowest temperature in the blackbody color table, kelvin. The table is log spaced.
// Source: gargantua design choice, see note.
#define BLACKBODY_T_MIN (1000.0f)

// Highest temperature in the blackbody color table, kelvin.
// Source: gargantua design choice, see note.
#define BLACKBODY_T_MAX (40000.0f)

// Entries in the blackbody color table.
// Source: gargantua design choice, see note.
#define BLACKBODY_TABLE_SIZE (256u)

// Hard cap on geodesic integration steps per ray in interactive rendering.
// Source: gargantua design choice, see note.
#define STEP_CAP_INTERACTIVE (256u)

// Hard cap on geodesic integration steps per ray for offline stills.
// Source: gargantua design choice, see note.
#define STEP_CAP_STILL (4096u)

// Affine step length is this fraction of the radius, clamped between STEP_MIN and STEP_MAX.
// Source: gargantua design choice, see note.
#define STEP_RADIUS_FACTOR (0.02f)

// Smallest affine step.
// Source: gargantua design choice, see note.
#define STEP_MIN (0.02f)

// Largest affine step.
// Source: gargantua design choice, see note.
#define STEP_MAX (0.5f)

// Stored samples per ray inside the volume cube for the bake strategy.
// Source: gargantua design choice, see note.
#define BAKE_SAMPLES (96u)

// Allowed relative drift of a ray's conserved energy and angular momentum over a 256 step integration.
// Source: gargantua design choice, see note.
#define DRIFT_BUDGET_INTERACTIVE (0.0001f)

// Allowed relative drift of a ray's conserved quantities over a 4096 step integration.
// Source: gargantua design choice, see note.
#define DRIFT_BUDGET_STILL (1e-05f)

// Stylized. Linear scale applied to the lensed image before tone mapping.
// Source: gargantua design choice, see note.
#define EXPOSURE_DEFAULT (1.0f)

// Stylized. Emission per particle at the peak temperature, per unit volume and path length, before the g^3 factor.
// Source: gargantua design choice, see note.
#define EMISSION_SCALE (0.0005f)

// Stylized. The simulated gas speed is compressed to beta = ceiling tanh(v / ceiling) before the Doppler factor, since pseudo Newtonian orbits exceed c inside r of about 4; the innermost stable orbit speed 0.61 maps to 0.52, close to the Schwarzschild value 0.5.
// Source: gargantua design choice, see note.
#define GAS_SPEED_CEILING (0.85f)

// Stylized. Extinction per unit path length per unit particle density; small so the far side of the disk and its lensed images stay visible.
// Source: gargantua design choice, see note.
#define VOLUME_OPACITY (0.0005f)

// Stylized. Scale of the procedural starfield behind escaped rays.
// Source: gargantua design choice, see note.
#define STAR_BRIGHTNESS (1.5f)

// Substeps simulated before an offline still so the plunging region is populated; the drift time from r = 7 to the innermost stable orbit is about 320 substeps.
// Source: gargantua design choice, see note.
#define STILL_SETTLE_STEPS (600u)

// Tile edge in pixels for offline stills; one tile is one command buffer, far below the 30 ms ceiling even at the still step cap.
// Source: gargantua design choice, see note.
#define STILL_TILE (128u)

// No single command buffer may carry more GPU work than this; the macOS GPU watchdog limit is a few seconds, leaving two orders of magnitude of margin.
// Source: gargantua design choice, see note.
#define COMMAND_BUFFER_BUDGET_MS (30.0f)

// Fraction of the device's recommended working set the program may allocate.
// Source: gargantua design choice, see note.
#define MEMORY_BUDGET_FRACTION (0.4f)

// Absolute cap on allocation regardless of the working set size.
// Source: gargantua design choice, see note.
#define MEMORY_BUDGET_CAP_BYTES (3000000000u)

#endif
