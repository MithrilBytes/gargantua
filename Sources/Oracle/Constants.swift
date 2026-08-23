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
    public static let stepMax = Constant<Double>("STEP_MAX", 0.5, source: design, note: "Largest affine step.")

    public static let bakeSamples = Constant<UInt32>(
        "BAKE_SAMPLES", 96,
        source: design,
        note: "Stored samples per ray inside the volume cube for the bake strategy.")

    public static let driftBudgetInteractive = Constant<Double>(
        "DRIFT_BUDGET_INTERACTIVE", 1e-4,
        source: design,
        note: "Allowed relative drift of a ray's conserved energy and angular momentum over a 256 step integration.")

    public static let driftBudgetStill = Constant<Double>(
        "DRIFT_BUDGET_STILL", 1e-5,
        source: design,
        note: "Allowed relative drift of a ray's conserved quantities over a 4096 step integration.")

    // MARK: Rendering

    public static let spriteRadius = Constant<Double>(
        "SPRITE_RADIUS", 0.08,
        source: design,
        note: "Stylized. World space radius of a particle point sprite.")

    public static let exposure = Constant<Double>(
        "EXPOSURE_DEFAULT", 0.35,
        source: design,
        note: "Stylized. Linear scale applied to accumulated emission before tone mapping.")

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
        captureRadius, escapeRadius, diskOuterRadius, feedInnerRadius, volumeHalfExtent,
        simulationTimestep, simulationSubsteps, dragAlpha, feedVelocityDispersion, diskAspectRatio,
        peakTemperature, zeroTorqueFloor, blackbodyMinTemperature, blackbodyMaxTemperature, blackbodyTableSize,
        stepCapInteractive, stepCapStill, stepRadiusFactor, stepMin, stepMax, bakeSamples,
        driftBudgetInteractive, driftBudgetStill,
        spriteRadius, exposure,
        commandBufferBudgetMilliseconds, memoryBudgetFraction, memoryBudgetCapBytes,
    ]
}
