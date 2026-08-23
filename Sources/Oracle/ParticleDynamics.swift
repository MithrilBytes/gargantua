import Foundation

public struct ParticleState: Sendable, Equatable {
    public var position: SIMD3<Double>
    public var velocity: SIMD3<Double>

    public init(position: SIMD3<Double>, velocity: SIMD3<Double>) {
        self.position = position
        self.velocity = velocity
    }

    public var radius: Double { (position * position).sum().squareRoot() }
    public var cylindricalRadius: Double { (position.x * position.x + position.y * position.y).squareRoot() }
    public var speed: Double { (velocity * velocity).sum().squareRoot() }
}

/// Semi implicit (symplectic) Euler with a velocity space drag term. The
/// update order is the contract the GPU kernel follows: gravity kick, drag,
/// then drift.
public struct ParticleDynamics: Sendable {
    public var potential: Potential
    public var dt: Double
    public var alpha: Double

    public init(potential: Potential, dt: Double = Constants.simulationTimestep.value, alpha: Double = Constants.dragAlpha.value) {
        self.potential = potential
        self.dt = dt
        self.alpha = alpha
    }

    public func step(_ state: inout ParticleState) {
        let r = state.radius
        let gravity = potential.acceleration(at: state.position)
        let omega = potential.angularFrequency(r)
        state.velocity += gravity * dt
        state.velocity -= state.velocity * (alpha * omega * dt)
        state.position += state.velocity * dt
    }

    /// Whether the step from `before` ended a particle: swept past the
    /// capture sphere, left the scene, or was kicked to a speed no bound
    /// orbit reaches. Mirrors the kernel.
    public static func removed(before: SIMD3<Double>, after state: ParticleState) -> Bool {
        let travel = state.position - before
        let lengthSquared = max((travel * travel).sum(), 1e-12)
        let along = min(max(-(before * travel).sum() / lengthSquared, 0.0), 1.0)
        let closestPoint = before + along * travel
        let closest = (closestPoint * closestPoint).sum().squareRoot()
        return closest < Constants.captureRadius.value
            || state.radius > Constants.escapeRadius.value
            || state.speed > Constants.plungeSpeedLimit.value
    }

    public func step(_ state: inout ParticleState, count: Int) {
        for _ in 0..<count { step(&state) }
    }

    /// Specific mechanical energy, conserved when alpha is zero.
    public func specificEnergy(_ state: ParticleState) -> Double {
        0.5 * state.speed * state.speed + potential.energy(state.radius)
    }

    /// Specific angular momentum about the z axis.
    public func angularMomentumZ(_ state: ParticleState) -> Double {
        state.position.x * state.velocity.y - state.position.y * state.velocity.x
    }
}
