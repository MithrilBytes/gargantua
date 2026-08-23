import Foundation

/// Null geodesics of the Schwarzschild metric in ingoing Eddington and
/// Finkelstein coordinates (v, r, phi), integrated in each ray's own orbital
/// plane with classical fourth order Runge Kutta. The equations are written
/// out from the Lagrangian and nothing is eliminated, so the conserved energy
/// and angular momentum can be watched as an error gauge.
///
/// Metric in the plane: ds^2 = -f dv^2 + 2 dv dr + r^2 dphi^2, f = 1 - 2/r.
/// Chandrasekhar 1983, The Mathematical Theory of Black Holes, ch. 3.
public enum Schwarzschild {
    public static let mass = 1.0

    public static func f(_ r: Double) -> Double {
        1.0 - Constants.schwarzschildRadius.value / r
    }

    /// Coordinates and their affine parameter derivatives.
    public struct RayState: Sendable, Equatable {
        public var v: Double
        public var r: Double
        public var phi: Double
        public var vDot: Double
        public var rDot: Double
        public var phiDot: Double

        public init(v: Double, r: Double, phi: Double, vDot: Double, rDot: Double, phiDot: Double) {
            self.v = v
            self.r = r
            self.phi = phi
            self.vDot = vDot
            self.rDot = rDot
            self.phiDot = phiDot
        }

        static func + (a: RayState, b: RayState) -> RayState {
            RayState(v: a.v + b.v, r: a.r + b.r, phi: a.phi + b.phi, vDot: a.vDot + b.vDot, rDot: a.rDot + b.rDot, phiDot: a.phiDot + b.phiDot)
        }

        static func * (a: RayState, s: Double) -> RayState {
            RayState(v: a.v * s, r: a.r * s, phi: a.phi * s, vDot: a.vDot * s, rDot: a.rDot * s, phiDot: a.phiDot * s)
        }
    }

    /// A ray with the plane it lives in and the constants it was born with.
    public struct Ray: Sendable {
        public var state: RayState
        /// Unit vector toward the launch point.
        public let e1: SIMD3<Double>
        /// Unit vector in the plane, perpendicular to e1, along the launch direction.
        public let e2: SIMD3<Double>
        public let energy: Double
        public let angularMomentum: Double

        public var position: SIMD3<Double> {
            state.r * (cos(state.phi) * e1 + sin(state.phi) * e2)
        }

        /// Spatial direction as measured by a static observer at the ray's
        /// current radius; unit length.
        public var direction: SIMD3<Double> {
            let radial = cos(state.phi) * e1 + sin(state.phi) * e2
            let tangential = -sin(state.phi) * e1 + cos(state.phi) * e2
            let local = state.rDot / max(f(state.r), 1e-6).squareRoot() * radial + state.r * state.phiDot * tangential
            let length = (local * local).sum().squareRoot()
            return length > 0 ? local / length : radial
        }

        /// Impact parameter L / E.
        public var impactParameter: Double { angularMomentum / energy }
    }

    /// Launch from a point in a direction as measured by a static observer
    /// there. The affine parameter is scaled so the locally measured photon
    /// energy at launch is one.
    public static func launch(from origin: SIMD3<Double>, direction d: SIMD3<Double>) -> Ray {
        let r0 = (origin * origin).sum().squareRoot()
        let e1 = origin / r0
        let unit = d / (d * d).sum().squareRoot()
        let dr = (unit * e1).sum()
        var perpendicular = unit - dr * e1
        var dphi = (perpendicular * perpendicular).sum().squareRoot()
        if dphi < 1e-12 {
            let helper = abs(e1.x) < 0.9 ? SIMD3(1.0, 0.0, 0.0) : SIMD3(0.0, 1.0, 0.0)
            perpendicular = helper - (helper * e1).sum() * e1
            perpendicular /= (perpendicular * perpendicular).sum().squareRoot()
            dphi = 0.0
        } else {
            perpendicular /= dphi
        }
        let f0 = f(r0)
        let state = RayState(v: 0.0, r: r0, phi: 0.0,
                             vDot: (1.0 + dr) / f0.squareRoot(),
                             rDot: f0.squareRoot() * dr,
                             phiDot: dphi / r0)
        return Ray(state: state, e1: e1, e2: perpendicular, energy: energy(state), angularMomentum: angularMomentum(state))
    }

    /// Launch from radius `radius` toward the hole with impact parameter b.
    public static func launch(radius: Double, impactParameter b: Double) -> Ray {
        let dphi = b * f(radius).squareRoot() / radius
        let dr = -(max(0.0, 1.0 - dphi * dphi)).squareRoot()
        return launch(from: SIMD3(radius, 0.0, 0.0), direction: SIMD3(dr, dphi, 0.0))
    }

    public static func energy(_ s: RayState) -> Double {
        f(s.r) * s.vDot - s.rDot
    }

    public static func angularMomentum(_ s: RayState) -> Double {
        s.r * s.r * s.phiDot
    }

    /// The null condition, zero for light.
    public static func nullResidual(_ s: RayState) -> Double {
        -f(s.r) * s.vDot * s.vDot + 2.0 * s.vDot * s.rDot + s.r * s.r * s.phiDot * s.phiDot
    }

    /// Geodesic equations from the Euler Lagrange equations of
    /// L = (1/2)(-f vDot^2 + 2 vDot rDot + r^2 phiDot^2).
    public static func derivative(_ s: RayState) -> RayState {
        let r = s.r
        let vDotDot = -s.vDot * s.vDot / (r * r) + r * s.phiDot * s.phiDot
        let rDotDot = 2.0 * s.rDot * s.vDot / (r * r) + f(r) * (r * s.phiDot * s.phiDot - s.vDot * s.vDot / (r * r))
        let phiDotDot = -2.0 * s.rDot * s.phiDot / r
        return RayState(v: s.vDot, r: s.rDot, phi: s.phiDot, vDot: vDotDot, rDot: rDotDot, phiDot: phiDotDot)
    }

    /// Classical fourth order Runge Kutta.
    public static func step(_ s: RayState, h: Double) -> RayState {
        let k1 = derivative(s)
        let k2 = derivative(s + k1 * (0.5 * h))
        let k3 = derivative(s + k2 * (0.5 * h))
        let k4 = derivative(s + k3 * h)
        return s + (k1 + k2 * 2.0 + k3 * 2.0 + k4) * (h / 6.0)
    }

    public struct Settings: Sendable {
        public var stepFactor: Double
        public var stepMin: Double
        public var stepMax: Double
        public var captureRadius: Double
        public var escapeRadius: Double
        public var stepCap: Int
        /// Step policy while the ray is too far from the disk slab to sample anything.
        public var emptyStepFactor: Double
        public var emptyStepMax: Double

        public init(stepFactor: Double = Constants.stepRadiusFactor.value,
                    stepMin: Double = Constants.stepMin.value,
                    stepMax: Double = Constants.stepMax.value,
                    captureRadius: Double = Constants.captureRadius.value,
                    escapeRadius: Double = Constants.escapeRadius.value,
                    stepCap: Int,
                    emptyStepFactor: Double? = nil,
                    emptyStepMax: Double? = nil) {
            self.stepFactor = stepFactor
            self.stepMin = stepMin
            self.stepMax = stepMax
            self.captureRadius = captureRadius
            self.escapeRadius = escapeRadius
            self.stepCap = stepCap
            self.emptyStepFactor = emptyStepFactor ?? stepFactor
            self.emptyStepMax = emptyStepMax ?? stepMax
        }

        public static let interactive = Settings(stepCap: Int(Constants.stepCapInteractive.value),
                                                 emptyStepFactor: Constants.emptyStepFactorInteractive.value,
                                                 emptyStepMax: Constants.emptyStepMaxInteractive.value)
        public static let still = Settings(stepCap: Int(Constants.stepCapStill.value),
                                           emptyStepFactor: Constants.emptyStepFactorStill.value,
                                           emptyStepMax: Constants.emptyStepMaxStill.value)

        public func stepLength(at r: Double) -> Double {
            min(max(stepFactor * r, stepMin), stepMax)
        }

        /// A ray farther from the disk slab than the coarse step it is about
        /// to take cannot land inside the slab; the coarser policy applies.
        public func stepLength(at r: Double, z: Double) -> Double {
            let coarse = min(max(emptyStepFactor * r, stepMin), emptyStepMax)
            if abs(z) > Constants.diskSlabHalfHeight.value + coarse { return coarse }
            return stepLength(at: r)
        }
    }

    public enum Outcome: Sendable, Equatable {
        case captured, escaped, exhausted
    }

    public struct Result: Sendable {
        public let ray: Ray
        public let outcome: Outcome
        public let steps: Int
        /// Largest relative deviation of E or L from their launch values.
        public let drift: Double
    }

    /// Integrate until capture, escape or the step cap.
    public static func integrate(_ launch: Ray, settings: Settings) -> Result {
        var ray = launch
        var steps = 0
        var drift = 0.0
        let lScale = max(abs(launch.angularMomentum), 1e-3)
        while steps < settings.stepCap {
            let h = settings.stepLength(at: ray.state.r, z: ray.position.z)
            ray.state = step(ray.state, h: h)
            steps += 1
            let eDrift = abs(energy(ray.state) - launch.energy) / abs(launch.energy)
            let lDrift = abs(angularMomentum(ray.state) - launch.angularMomentum) / lScale
            drift = max(drift, max(eDrift, lDrift))
            if ray.state.r <= settings.captureRadius {
                return Result(ray: ray, outcome: .captured, steps: steps, drift: drift)
            }
            if ray.state.r >= settings.escapeRadius {
                return Result(ray: ray, outcome: .escaped, steps: steps, drift: drift)
            }
        }
        return Result(ray: ray, outcome: .exhausted, steps: steps, drift: drift)
    }

    /// Total redshift factor g = E_observed / E_emitted for light leaving gas
    /// that a static observer at radius r sees moving with velocity `gas`,
    /// reaching a distant observer: the gravitational factor sqrt(f) times
    /// the Doppler factor 1 / (gamma (1 - n . beta)), where n is the photon's
    /// direction of travel. `direction` is the marched direction, from the
    /// eye toward the gas, so n is its opposite.
    /// The simulated velocity stands in for the locally measured velocity
    /// after a smooth compression below c. Mirrors march.metal.
    public static func redshiftFactor(radius r: Double, direction: SIMD3<Double>, gas: SIMD3<Double>) -> Double {
        let ceiling = Constants.gasSpeedCeiling.value
        let speed = (gas * gas).sum().squareRoot()
        let beta = speed > 0 ? ceiling * tanh(speed / ceiling) : 0.0
        let velocity = speed > 0 ? gas * (beta / speed) : SIMD3(repeating: 0.0)
        let gamma = 1.0 / (1.0 - beta * beta).squareRoot()
        return max(f(r), 0.0).squareRoot() / (gamma * (1.0 + (direction * velocity).sum()))
    }

    /// Angle between the launch direction and the final direction, in the
    /// orbital plane, positive toward the hole.
    public static func deflection(from launch: Ray, to result: Result) -> Double {
        func planar(_ ray: Ray) -> SIMD2<Double> {
            let d = ray.direction
            return SIMD2((d * ray.e1).sum(), (d * ray.e2).sum())
        }
        let a = planar(launch)
        let b = planar(result.ray)
        return atan2(a.x * b.y - a.y * b.x, a.x * b.x + a.y * b.y)
    }

    /// Bisect the impact parameter separating captured from escaping rays.
    /// Rays that run out of steps sit on the boundary and end the search.
    public static func criticalImpactParameter(launchRadius: Double, settings: Settings, iterations: Int = 60) -> Double {
        var low = 3.0
        var high = 8.0
        for _ in 0..<iterations {
            let mid = 0.5 * (low + high)
            let result = integrate(launch(radius: launchRadius, impactParameter: mid), settings: settings)
            switch result.outcome {
            case .captured: low = mid
            case .escaped: high = mid
            case .exhausted: return mid
            }
        }
        return 0.5 * (low + high)
    }
}
