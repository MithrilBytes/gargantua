import Foundation

/// Null geodesics of the Kerr metric in Boyer and Lindquist coordinates,
/// double precision, no cleverness. The Hamiltonian is the separable form
/// with the conserved energy and axial angular momentum as parameters
/// (Chandrasekhar 1983, ch. 7; Bardeen 1973, Les Houches; James, von
/// Tunzelmann, Franklin and Thorne 2015, appendix A), so the monitored
/// error gauges are the Carter constant and the null residual.
public enum KerrGeodesic {
    public struct Spacetime: Sendable {
        public let spin: Double
        public init(spin: Double) {
            precondition(spin >= 0 && spin < 1)
            self.spin = spin
        }

        public var outerHorizon: Double { 1.0 + (1.0 - spin * spin).squareRoot() }
        public func delta(_ r: Double) -> Double { r * r - 2.0 * r + spin * spin }
        public func sigma(_ r: Double, _ theta: Double) -> Double {
            let c = cos(theta)
            return r * r + spin * spin * c * c
        }
    }

    /// Coordinates and momenta; E and L ride along as parameters.
    public struct RayState: Sendable {
        public var r: Double
        public var theta: Double
        public var phi: Double
        public var pr: Double
        public var ptheta: Double
        public var energy: Double
        public var angularMomentum: Double

        static func + (a: RayState, b: RayState) -> RayState {
            var out = a
            out.r += b.r; out.theta += b.theta; out.phi += b.phi
            out.pr += b.pr; out.ptheta += b.ptheta
            return out
        }

        static func * (a: RayState, s: Double) -> RayState {
            var out = a
            out.r *= s; out.theta *= s; out.phi *= s
            out.pr *= s; out.ptheta *= s
            return out
        }
    }

    /// The radial and angular potential pieces, expanded so the axis is
    /// regular for rays with no axial angular momentum.
    static func potentials(_ s: Spacetime, _ state: RayState) -> (p: Double, g: Double) {
        let a = s.spin
        let e = state.energy, l = state.angularMomentum
        let p = (state.r * state.r + a * a) * e - a * l
        let sin2 = max(sin(state.theta) * sin(state.theta), 1e-12)
        let g = l * l / sin2 - 2.0 * a * e * l + a * a * e * e * sin2
        return (p, g)
    }

    /// 2 Sigma H, zero for light.
    public static func nullResidual(_ s: Spacetime, _ state: RayState) -> Double {
        let delta = s.delta(state.r)
        let (p, g) = potentials(s, state)
        return delta * state.pr * state.pr + state.ptheta * state.ptheta - p * p / delta + g
    }

    /// Carter's constant, the fourth integral of motion.
    public static func carter(_ s: Spacetime, _ state: RayState) -> Double {
        let c = cos(state.theta)
        let sin2 = max(sin(state.theta) * sin(state.theta), 1e-12)
        let term = state.angularMomentum * state.angularMomentum / sin2 - s.spin * s.spin * state.energy * state.energy
        return state.ptheta * state.ptheta + c * c * term
    }

    /// Hamilton's equations, exact including the off shell Sigma terms.
    public static func derivative(_ s: Spacetime, _ state: RayState) -> RayState {
        let a = s.spin
        let e = state.energy, l = state.angularMomentum
        let r = state.r, theta = state.theta
        let delta = s.delta(r)
        let sigma = s.sigma(r, theta)
        let deltaPrime = 2.0 * r - 2.0
        let sinTheta = sin(theta), cosTheta = cos(theta)
        let sin2 = max(sinTheta * sinTheta, 1e-12)
        let (p, g) = potentials(s, state)
        let f = delta * state.pr * state.pr + state.ptheta * state.ptheta - p * p / delta + g
        let hamiltonian = f / (2.0 * sigma)

        // dF/dr and dF/dtheta.
        let pPrime = 2.0 * r * e
        let fr = deltaPrime * state.pr * state.pr - 2.0 * p * pPrime / delta + p * p * deltaPrime / (delta * delta)
        let gTheta = -2.0 * l * l * cosTheta / (sin2 * max(sinTheta, 1e-9)) + 2.0 * a * a * e * e * sinTheta * cosTheta
        let ftheta = gTheta
        let sigmaR = 2.0 * r
        let sigmaTheta = -2.0 * a * a * sinTheta * cosTheta

        var out = state
        out.r = delta * state.pr / sigma
        out.theta = state.ptheta / sigma
        out.phi = (a * p / delta + l / sin2 - a * e) / sigma
        out.pr = -(fr / (2.0 * sigma) - hamiltonian * sigmaR / sigma)
        out.ptheta = -(ftheta / (2.0 * sigma) - hamiltonian * sigmaTheta / sigma)
        return out
    }

    public static func step(_ s: Spacetime, _ state: RayState, h: Double) -> RayState {
        let k1 = derivative(s, state)
        let k2 = derivative(s, state + k1 * (0.5 * h))
        let k3 = derivative(s, state + k2 * (0.5 * h))
        let k4 = derivative(s, state + k3 * h)
        return state + (k1 + k2 * 2.0 + k3 * 2.0 + k4) * (h / 6.0)
    }

    /// Boyer and Lindquist radius of a Cartesian point.
    public static func radius(_ s: Spacetime, of point: SIMD3<Double>) -> Double {
        let a2 = s.spin * s.spin
        let rho2 = (point * point).sum()
        let half = 0.5 * (rho2 - a2)
        return (half + (half * half + a2 * point.z * point.z).squareRoot()).squareRoot()
    }

    /// Launch from a Cartesian point along a locally measured direction, the
    /// direction decomposed against the spherical frame (exact for the
    /// oracle and the GPU alike, since both sides share this convention;
    /// the Boyer and Lindquist embedding differs from spherical by order
    /// spin squared over radius squared at the camera).
    public static func launch(_ s: Spacetime, from origin: SIMD3<Double>, direction: SIMD3<Double>) -> RayState {
        let a = s.spin
        let r = radius(s, of: origin)
        let rho = (origin * origin).sum().squareRoot()
        let theta = acos(min(max(origin.z / rho, -1.0), 1.0))
        let phi = atan2(origin.y, origin.x)
        let d = direction / (direction * direction).sum().squareRoot()

        let sinTheta = sin(theta), cosTheta = cos(theta)
        let rHat = SIMD3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta)
        let thetaHat = SIMD3(cosTheta * cos(phi), cosTheta * sin(phi), -sinTheta)
        let phiHat = SIMD3(-sin(phi), cos(phi), 0.0)
        let nr = (d * rHat).sum()
        let ntheta = (d * thetaHat).sum()
        let nphi = (d * phiHat).sum()

        let delta = s.delta(r)
        let sigma = s.sigma(r, theta)
        let sin2 = max(sinTheta * sinTheta, 1e-12)
        let gtt = -(1.0 - 2.0 * r / sigma)
        let gtphi = -2.0 * a * r * sin2 / sigma
        let gphiphi = (r * r + a * a + 2.0 * a * a * r * sin2 / sigma) * sin2
        let grr = sigma / delta
        let gthth = sigma

        // Static observer tetrad; the camera stays far outside the ergosphere.
        let ut = 1.0 / (-gtt).squareRoot()
        let phiNorm = (gphiphi - gtphi * gtphi / gtt).squareRoot()
        // p = e_that + nr e_rhat + ntheta e_thetahat + nphi e_phihat, local energy one.
        let pt = ut + nphi * (-gtphi / gtt) / phiNorm
        let pphi = nphi / phiNorm
        let prUp = nr / grr.squareRoot()
        let pthUp = ntheta / gthth.squareRoot()

        var state = RayState(r: r, theta: theta, phi: phi, pr: 0, ptheta: 0, energy: 0, angularMomentum: 0)
        state.energy = -(gtt * pt + gtphi * pphi)
        state.angularMomentum = gtphi * pt + gphiphi * pphi
        state.pr = grr * prUp
        state.ptheta = gthth * pthUp
        return state
    }

    public static func position(_ s: Spacetime, _ state: RayState) -> SIMD3<Double> {
        let radial = (state.r * state.r + s.spin * s.spin).squareRoot()
        let sinTheta = sin(state.theta)
        return SIMD3(radial * sinTheta * cos(state.phi), radial * sinTheta * sin(state.phi), state.r * cos(state.theta))
    }

    public struct Settings: Sendable {
        public var stepFactor: Double
        public var stepMin: Double
        public var stepMax: Double
        public var captureMargin: Double
        public var escapeRadius: Double
        public var stepCap: Int

        public init(stepFactor: Double = Constants.stepRadiusFactor.value,
                    stepMin: Double = 0.005,
                    stepMax: Double = Constants.stepMax.value,
                    captureMargin: Double = Constants.kerrCaptureMargin.value,
                    escapeRadius: Double = Constants.escapeRadius.value,
                    stepCap: Int) {
            self.stepFactor = stepFactor
            self.stepMin = stepMin
            self.stepMax = stepMax
            self.captureMargin = captureMargin
            self.escapeRadius = escapeRadius
            self.stepCap = stepCap
        }
    }

    public enum Outcome: Sendable, Equatable {
        case captured, escaped, exhausted
    }

    public struct Result: Sendable {
        public let state: RayState
        public let outcome: Outcome
        public let steps: Int
        /// Largest relative drift of the Carter constant, and of the null
        /// residual against the ray's energy scale.
        public let drift: Double
    }

    /// Step length: proportional to radius, shrinking near the horizon
    /// where the momenta steepen as one over Delta.
    public static func stepLength(_ s: Spacetime, _ state: RayState, settings: Settings) -> Double {
        let aboveHorizon = state.r - s.outerHorizon
        let near = 0.2 * aboveHorizon
        return min(max(min(settings.stepFactor * state.r, near), settings.stepMin), settings.stepMax)
    }

    public static func integrate(_ s: Spacetime, from launch: RayState, settings: Settings) -> Result {
        var state = launch
        let carter0 = carter(s, launch)
        let scale = max(abs(carter0), launch.energy * launch.energy)
        var drift = 0.0
        var steps = 0
        let captureRadius = s.outerHorizon + settings.captureMargin
        while steps < settings.stepCap {
            state = step(s, state, h: stepLength(s, state, settings: settings))
            steps += 1
            let carterDrift = abs(carter(s, state) - carter0) / scale
            let nullDrift = abs(nullResidual(s, state)) / (scale * max(state.r * state.r, 1.0))
            drift = max(drift, max(carterDrift, nullDrift))
            if state.r <= captureRadius {
                return Result(state: state, outcome: .captured, steps: steps, drift: drift)
            }
            if state.r >= settings.escapeRadius {
                return Result(state: state, outcome: .escaped, steps: steps, drift: drift)
            }
        }
        return Result(state: state, outcome: .exhausted, steps: steps, drift: drift)
    }

    /// Impact parameters of the shadow edge for a spherical photon orbit at
    /// Boyer and Lindquist radius rc. Bardeen, J. M., 1973, in Black Holes,
    /// eds. DeWitt and DeWitt, Gordon and Breach.
    public static func criticalXi(spin a: Double, orbitRadius rc: Double) -> Double {
        (rc * rc * (3.0 - rc) - a * a * (rc + 1.0)) / (a * (rc - 1.0))
    }

    public static func criticalEta(spin a: Double, orbitRadius rc: Double) -> Double {
        rc * rc * rc * (4.0 * a * a - rc * (rc - 3.0) * (rc - 3.0)) / (a * a * (rc - 1.0) * (rc - 1.0))
    }

    /// Equatorial photon orbit radii: the two roots of eta = 0 bracketing
    /// the polar orbit, prograde inside, retrograde outside.
    public static func equatorialPhotonOrbits(spin a: Double) -> (prograde: Double, retrograde: Double) {
        let prograde = 2.0 * (1.0 + cos(2.0 / 3.0 * acos(-a)))
        let retrograde = 2.0 * (1.0 + cos(2.0 / 3.0 * acos(a)))
        return (prograde, retrograde)
    }
}
