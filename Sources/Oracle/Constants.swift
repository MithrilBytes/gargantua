/// A value that can be written as a Metal literal.
public protocol ConstantValue: Sendable {
    var metalLiteral: String { get }
}

extension Double: ConstantValue {
    public var metalLiteral: String {
        var text = "\(self)"
        if !text.contains(".") && !text.contains("e") { text += ".0" }
        return text + "f"
    }
}

extension UInt32: ConstantValue {
    public var metalLiteral: String { "\(self)u" }
}

/// Anything the generated Metal header can carry.
public protocol ConstantEntry: Sendable {
    var symbol: String { get }
    var metalLiteral: String { get }
    var source: String { get }
    var note: String { get }
}

/// One named number together with where it came from. Nothing numeric ships
/// without one of these, so a reader can always trace a figure to a source.
public struct Constant<Value: ConstantValue>: ConstantEntry {
    public let symbol: String
    public let value: Value
    public let source: String
    public let note: String

    public init(_ symbol: String, _ value: Value, source: String, note: String = "") {
        self.symbol = symbol
        self.value = value
        self.source = source
        self.note = note
    }

    public var metalLiteral: String { value.metalLiteral }
}

/// The single source of truth for every constant used by the simulation,
/// the renderer and the oracle. Geometrized units, G = c = M = 1, so every
/// length is in units of the black hole mass.
public enum Constants {
    static let chandrasekhar = "Chandrasekhar, S., 1983. The Mathematical Theory of Black Holes. Oxford University Press, ch. 3."
    static let bardeen = "Bardeen, J. M., Press, W. H. and Teukolsky, S. A., 1972. Rotating black holes: locally nonrotating frames, energy extraction, and scalar synchrotron radiation. ApJ 178, 347."
    static let paczynskiWiita = "Paczynski, B. and Wiita, P. J., 1980. Thick accretion disks and supercritical luminosities. A&A 88, 23."
    static let shakuraSunyaev = "Shakura, N. I. and Sunyaev, R. A., 1973. Black holes in binary systems. A&A 24, 337."
    public static let design = "gargantua design choice, see note."

    // MARK: Schwarzschild geometry

    public static let schwarzschildRadius = Constant<Double>(
        "R_SCHWARZSCHILD", 2.0,
        source: "Schwarzschild, K., 1916. Sitzungsberichte der Koniglich Preussischen Akademie der Wissenschaften, 189. " + chandrasekhar,
        note: "Event horizon at r = 2M in units where G = c = M = 1.")

    public static let photonSphere = Constant<Double>(
        "R_PHOTON_SPHERE", 3.0,
        source: chandrasekhar,
        note: "Unstable circular photon orbit at r = 3M.")

    public static let isco = Constant<Double>(
        "R_ISCO", 6.0,
        source: bardeen + " " + chandrasekhar,
        note: "Innermost stable circular orbit for a non rotating hole, r = 6M.")

    public static let marginallyBound = Constant<Double>(
        "R_MARGINALLY_BOUND", 4.0,
        source: bardeen,
        note: "Marginally bound circular orbit at r = 4M; also reproduced by the Paczynski and Wiita potential.")

    public static let criticalImpactParameter = Constant<Double>(
        "B_CRITICAL", 5.196152422706632,
        source: chandrasekhar + " Luminet, J.-P., 1979. Image of a spherical black hole with thin accretion disk. A&A 75, 228.",
        note: "Critical impact parameter 3 sqrt(3) M separating captured from escaping null geodesics; the shadow radius.")

    public static let weakDeflectionCoefficient = Constant<Double>(
        "WEAK_DEFLECTION_COEFFICIENT", 4.0,
        source: "Einstein, A., 1916. Die Grundlage der allgemeinen Relativitatstheorie. Annalen der Physik 49, 769. Weinberg, S., 1972. Gravitation and Cosmology. Wiley, ch. 8.",
        note: "Weak field light deflection is 4M / b for impact parameter b much larger than M.")

    // MARK: Scene radii

    public static let captureRadius = Constant<Double>(
        "R_CAPTURE", 2.02,
        source: design,
        note: "Rays and particles terminate here, one percent above the horizon, so single precision arithmetic never evaluates the metric at r = 2.")

    public static let escapeRadius = Constant<Double>(
        "R_ESCAPE", 60.0,
        source: design,
        note: "Rays and particles beyond this radius are treated as escaped.")

    public static let diskOuterRadius = Constant<Double>(
        "R_DISK_OUTER", 24.0,
        source: design,
        note: "Outer edge of the seeded disk and of the feeding annulus.")

    public static let feedInnerRadius = Constant<Double>(
        "R_FEED_INNER", 20.0,
        source: design,
        note: "Inner edge of the annulus where captured and escaped particles respawn.")

    public static let diskSlabHalfHeight = Constant<Double>(
        "DISK_SLAB_HALF_HEIGHT", 6.0,
        source: design,
        note: "Rays sample the volume only within this height of the disk plane. Seeding puts gas within 0.05 r Gaussian of the plane, so at the outer edge five sigma is 6; vertical oscillation amplitudes are conserved under gravity and shrink under drag.")

    public static let volumeHalfExtent = Constant<Double>(
        "VOLUME_HALF_EXTENT", 30.0,
        source: design,
        note: "Half width of the cube the splat pass bins particles into, centered on the hole.")

    // MARK: Particle dynamics

    public static let simulationTimestep = Constant<Double>(
        "SIM_DT", 0.1,
        source: "Hairer, E., Lubich, C. and Wanner, G., 2006. Geometric Numerical Integration, 2nd ed. Springer, ch. I.",
        note: "Fixed timestep per substep in code units. The innermost stable orbit has angular frequency 1 / sqrt(96) in the Paczynski and Wiita potential, so dt times omega is 0.0102, far inside the stability bound of 2 for symplectic Euler on harmonic motion.")

    public static let simulationSubsteps = Constant<UInt32>(
        "SIM_SUBSTEPS", 2,
        source: design,
        note: "Substeps per rendered frame.")

    public static let dragAlpha = Constant<Double>(
        "DRAG_ALPHA", 0.003,
        source: design,
        note: "Velocity space drag rate as a fraction of the local circular angular frequency; stands in for viscosity and drives the inward spiral.")

    public static let feedVelocityDispersion = Constant<Double>(
        "FEED_VELOCITY_DISPERSION", 0.02,
        source: design,
        note: "Gaussian velocity dispersion per component as a fraction of the local circular speed, applied at seeding and respawn.")

    public static let diskAspectRatio = Constant<Double>(
        "DISK_ASPECT", 0.05,
        source: "Pringle, J. E., 1981. Accretion discs in astrophysics. ARA&A 19, 137.",
        note: "Vertical Gaussian scale height as a fraction of radius; thin disk regime h / r much smaller than 1.")

    // MARK: Temperature and color

    public static let peakTemperature = Constant<Double>(
        "T_PEAK_DEFAULT", 8000.0,
        source: design,
        note: "Stylized. Peak of the thin disk temperature profile in kelvin; real disks peak far hotter than a monitor can show.")

    public static let zeroTorqueFloor = Constant<Double>(
        "ZERO_TORQUE_FLOOR", 0.01,
        source: design,
        note: "Stylized. Floor on the zero torque factor 1 - sqrt(r_isco / r) so gas inside the innermost stable orbit keeps a finite, cooler temperature instead of vanishing.")

    public static let blackbodyMinTemperature = Constant<Double>(
        "BLACKBODY_T_MIN", 1000.0,
        source: design,
        note: "Lowest temperature in the blackbody color table, kelvin. The table is log spaced.")

    public static let blackbodyMaxTemperature = Constant<Double>(
        "BLACKBODY_T_MAX", 40000.0,
        source: design,
        note: "Highest temperature in the blackbody color table, kelvin.")

    public static let cicCorners = Constant<UInt32>(
        "CIC_CORNERS", 8,
        source: "Hockney, R. W. and Eastwood, J. W., 1988. Computer Simulation Using Particles. Taylor and Francis, ch. 5 (cloud in cell weighting).",
        note: "Corners of the trilinear cloud in cell deposit. Interactive frames choose one corner per particle with the trilinear weights as probabilities, an unbiased estimate whose expectation is the exact deposit; stills deposit into all eight.")

    public static let blackbodyTableSize = Constant<UInt32>(
        "BLACKBODY_TABLE_SIZE", 256,
        source: design,
        note: "Entries in the blackbody color table.")

    // MARK: Ray marching

    public static let stepCapInteractive = Constant<UInt32>(
        "STEP_CAP_INTERACTIVE", 256,
        source: design,
        note: "Hard cap on geodesic integration steps per ray in interactive rendering.")

    public static let stepCapStill = Constant<UInt32>(
        "STEP_CAP_STILL", 4096,
        source: design,
        note: "Hard cap on geodesic integration steps per ray for offline stills.")

    public static let stepRadiusFactor = Constant<Double>(
        "STEP_RADIUS_FACTOR", 0.02,
        source: design,
        note: "Affine step length is this fraction of the radius, clamped between STEP_MIN and STEP_MAX.")

    public static let stepMin = Constant<Double>("STEP_MIN", 0.02, source: design, note: "Smallest affine step.")
    public static let stepMax = Constant<Double>("STEP_MAX", 0.5, source: design, note: "Largest affine step while a ray is near the disk slab, about one voxel of the default volume, so the gather resolves it.")

    public static let emptyStepFactorInteractive = Constant<Double>(
        "STEP_FACTOR_EMPTY_INTERACTIVE", 0.1,
        source: design,
        note: "Interactive step factor while a ray is farther from the disk slab than the step it would take; nothing can be sampled there and fourth order accuracy allows it. Chosen from the docs/lab/02 sweep: E and L drift 1.5e-5 against the 1e-4 interactive budget, image difference 1.2e-3.")

    public static let emptyStepMaxInteractive = Constant<Double>(
        "STEP_MAX_EMPTY_INTERACTIVE", 3.0,
        source: design,
        note: "Largest interactive step away from the slab, from the docs/lab/02 sweep.")

    public static let emptyStepFactorStill = Constant<Double>(
        "STEP_FACTOR_EMPTY_STILL", 0.06,
        source: design,
        note: "Still render step factor away from the slab; gentler than interactive so the drift stays under the tighter 1e-5 still budget (measured 3e-6 in the docs/lab/02 sweep).")

    public static let emptyStepMaxStill = Constant<Double>(
        "STEP_MAX_EMPTY_STILL", 1.5,
        source: design,
        note: "Largest still render step away from the slab, from the docs/lab/02 sweep.")

    public static let marchThreadgroupWidth = Constant<UInt32>(
        "MARCH_THREADGROUP_WIDTH", 8,
        source: design,
        note: "Threadgroup shape for the ray kernels; 8 by 8 measured 10 percent faster than the previous 32 by 4 in the docs/lab/03 sweep.")

    public static let marchThreadgroupHeight = Constant<UInt32>(
        "MARCH_THREADGROUP_HEIGHT", 8,
        source: design,
        note: "See MARCH_THREADGROUP_WIDTH.")

    public static let bakeSamples = Constant<UInt32>(
        "BAKE_SAMPLES", 96,
        source: design,
        note: "Stored samples per ray inside the volume cube for the bake strategy.")

    public static let bakeSpacingVoxels = Constant<Double>(
        "BAKE_SPACING_VOXELS", 0.5,
        source: design,
        note: "Minimum path length between stored bake samples, in voxels, so small steps near the hole do not exhaust the sample budget on one voxel.")

    public static let bakeFrames = Constant<UInt32>(
        "BAKE_FRAMES", 4,
        source: design,
        note: "Frames a progressive rebake is spread across after the camera stops moving.")

    public static let sweepTableSize = Constant<UInt32>(
        "SWEEP_TABLE_SIZE", 1024,
        source: design,
        note: "Entries in each sweep table the march looks bending up from outside the integration sphere.")

    public static let driftBudgetInteractive = Constant<Double>(
        "DRIFT_BUDGET_INTERACTIVE", 1e-4,
        source: design,
        note: "Allowed relative drift of a ray's conserved energy and angular momentum over a 256 step integration.")

    public static let driftBudgetStill = Constant<Double>(
        "DRIFT_BUDGET_STILL", 1e-5,
        source: design,
        note: "Allowed relative drift of a ray's conserved quantities over a 4096 step integration.")

    // MARK: Rendering

    public static let exposure = Constant<Double>(
        "EXPOSURE_DEFAULT", 1.0,
        source: design,
        note: "Stylized. Linear scale applied to the lensed image before tone mapping.")

    public static let emissionScale = Constant<Double>(
        "EMISSION_SCALE", 0.0005,
        source: design,
        note: "Stylized. Emission per particle at the peak temperature, per unit volume and path length, before the g^3 factor.")

    public static let gasSpeedCeiling = Constant<Double>(
        "GAS_SPEED_CEILING", 0.85,
        source: design,
        note: "Stylized. The simulated gas speed is compressed to beta = ceiling tanh(v / ceiling) before the Doppler factor, since pseudo Newtonian orbits exceed c inside r of about 4; the innermost stable orbit speed 0.61 maps to 0.52, close to the Schwarzschild value 0.5.")

    public static let volumeOpacity = Constant<Double>(
        "VOLUME_OPACITY", 0.0005,
        source: design,
        note: "Stylized. Extinction per unit path length per unit particle density; small so the far side of the disk and its lensed images stay visible.")

    public static let starBrightness = Constant<Double>(
        "STAR_BRIGHTNESS", 1.5,
        source: design,
        note: "Stylized. Scale of the procedural starfield behind escaped rays.")

    public static let stillSettleSteps = Constant<UInt32>(
        "STILL_SETTLE_STEPS", 600,
        source: design,
        note: "Substeps simulated before an offline still so the plunging region is populated; the drift time from r = 7 to the innermost stable orbit is about 320 substeps.")

    public static let stillTile = Constant<UInt32>(
        "STILL_TILE", 128,
        source: design,
        note: "Tile edge in pixels for offline stills; one tile is one command buffer, far below the 30 ms ceiling even at the still step cap.")

    // MARK: Safety

    public static let commandBufferBudgetMilliseconds = Constant<Double>(
        "COMMAND_BUFFER_BUDGET_MS", 30.0,
        source: design,
        note: "No single command buffer may carry more GPU work than this; the macOS GPU watchdog limit is a few seconds, leaving two orders of magnitude of margin.")

    public static let memoryBudgetFraction = Constant<Double>(
        "MEMORY_BUDGET_FRACTION", 0.4,
        source: design,
        note: "Fraction of the device's recommended working set the program may allocate.")

    public static let memoryBudgetCapBytes = Constant<UInt32>(
        "MEMORY_BUDGET_CAP_BYTES", 3_000_000_000,
        source: design,
        note: "Absolute cap on allocation regardless of the working set size.")

    /// Every constant, in the order they appear in the generated header.
    public static let all: [any ConstantEntry] = [
        schwarzschildRadius, photonSphere, isco, marginallyBound, criticalImpactParameter, weakDeflectionCoefficient,
        captureRadius, escapeRadius, diskOuterRadius, feedInnerRadius, diskSlabHalfHeight, volumeHalfExtent,
        simulationTimestep, simulationSubsteps, dragAlpha, feedVelocityDispersion, diskAspectRatio,
        peakTemperature, zeroTorqueFloor, cicCorners, blackbodyMinTemperature, blackbodyMaxTemperature, blackbodyTableSize,
        stepCapInteractive, stepCapStill, stepRadiusFactor, stepMin, stepMax,
        emptyStepFactorInteractive, emptyStepMaxInteractive, emptyStepFactorStill, emptyStepMaxStill,
        marchThreadgroupWidth, marchThreadgroupHeight, bakeSamples, bakeSpacingVoxels, bakeFrames, sweepTableSize,
        driftBudgetInteractive, driftBudgetStill,
        exposure, emissionScale, gasSpeedCeiling, volumeOpacity, starBrightness, stillSettleSteps, stillTile,
        commandBufferBudgetMilliseconds, memoryBudgetFraction, memoryBudgetCapBytes,
    ]
}
