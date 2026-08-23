import Foundation

/// Central potentials for the test particle disk. Radial derivatives are
/// written out by hand so the oracle has nothing clever in it.
public enum Potential: String, Sendable, CaseIterable {
    /// Phi(r) = -1 / r.
    case newtonian
    /// Phi(r) = -1 / (r - 2), which reproduces the innermost stable circular
    /// orbit at r = 6 and the marginally bound orbit at r = 4 with Newtonian
    /// arithmetic. Paczynski and Wiita 1980, A&A 88, 23.
    case paczynskiWiita

    static let singularity = Constants.schwarzschildRadius.value

    /// Guard against the pole at r = 2 so a stray particle never produces a NaN.
    static func offset(_ r: Double) -> Double {
        max(r - singularity, 1e-6)
    }

    public func energy(_ r: Double) -> Double {
        switch self {
        case .newtonian: return -1.0 / r
        case .paczynskiWiita: return -1.0 / Potential.offset(r)
        }
    }

    /// d Phi / d r.
    public func gradient(_ r: Double) -> Double {
        switch self {
        case .newtonian: return 1.0 / (r * r)
        case .paczynskiWiita:
            let d = Potential.offset(r)
            return 1.0 / (d * d)
        }
    }

    /// Speed of a circular orbit, sqrt(r dPhi/dr).
    public func circularSpeed(_ r: Double) -> Double {
        (r * gradient(r)).squareRoot()
    }

    /// Angular frequency of a circular orbit, the inverse dynamical time.
    public func angularFrequency(_ r: Double) -> Double {
        circularSpeed(r) / r
    }

    public func circularEnergy(_ r: Double) -> Double {
        let v = circularSpeed(r)
        return 0.5 * v * v + energy(r)
    }

    public func circularAngularMomentum(_ r: Double) -> Double {
        r * circularSpeed(r)
    }

    /// Gravitational acceleration at a point.
    public func acceleration(at position: SIMD3<Double>) -> SIMD3<Double> {
        let r = (position * position).sum().squareRoot()
        return position * (-gradient(r) / r)
    }
}
