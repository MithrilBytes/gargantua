import Foundation

/// The thin disk profile the particles carry and the steady state the drag
/// driven inflow relaxes to. Everything here is radial and analytic.
public enum DiskModel {
    public static let isco = Constants.isco.value
    public static let outer = Constants.diskOuterRadius.value
    public static let feedInner = Constants.feedInnerRadius.value

    /// Radius where the unfloored profile peaks, (49 / 36) r_isco.
    public static let peakRadius = isco * 49.0 / 36.0

    /// Unnormalized profile (r_isco / r)^(3/4) (1 - sqrt(r_isco / r))^(1/4)
    /// with the zero torque factor floored below the innermost stable orbit.
    /// Shakura and Sunyaev 1973 radial scaling; zero torque boundary factor
    /// after Page and Thorne 1974, ApJ 191, 499.
    static func shape(_ r: Double, floor: Double) -> Double {
        let x = isco / r
        let torque = max(1.0 - x.squareRoot(), floor)
        return pow(x, 0.75) * pow(torque, 0.25)
    }

    /// Temperature in kelvin, normalized so the profile peaks at `peak`.
    public static func temperature(radius r: Double, peak: Double = Constants.peakTemperature.value) -> Double {
        let floor = Constants.zeroTorqueFloor.value
        return peak * shape(r, floor: floor) / shape(peakRadius, floor: floor)
    }

    /// Fraction of the injected mass that flows inward past radius r when the
    /// feeding annulus injects uniformly per unit area.
    public static func massFluxFraction(radius r: Double) -> Double {
        if r <= feedInner { return 1.0 }
        if r >= outer { return 0.0 }
        return (outer * outer - r * r) / (outer * outer - feedInner * feedInner)
    }

    /// Steady state surface density, up to a constant. For circular orbits
    /// under drag alpha the radial drift speed is 2 alpha omega r (r - 2) /
    /// (r - 6) in the Paczynski and Wiita potential, so continuity gives
    /// Sigma proportional to Mdot(r) (r - 6) / r^(3/2). The profile goes to
    /// zero linearly at the innermost stable orbit.
    public static func steadySurfaceDensity(radius r: Double) -> Double {
        if r <= isco || r >= outer { return 0.0 }
        return massFluxFraction(radius: r) * (r - isco) / pow(r, 1.5)
    }

    /// Particles per unit radius, 2 pi r Sigma(r).
    public static func radialNumberDensity(radius r: Double) -> Double {
        2.0 * Double.pi * r * steadySurfaceDensity(radius: r)
    }

    /// Table mapping a uniform deviate in [0, 1] to a radius drawn from the
    /// steady profile. Entry k corresponds to u = k / (count - 1).
    public static func radialInverseCdf(count: Int, resolution: Int = 8192) -> [Double] {
        let r0 = isco, r1 = outer
        let dr = (r1 - r0) / Double(resolution)
        var cumulative = [Double](repeating: 0.0, count: resolution + 1)
        var previous = radialNumberDensity(radius: r0)
        for i in 1...resolution {
            let r = r0 + Double(i) * dr
            let density = radialNumberDensity(radius: r)
            cumulative[i] = cumulative[i - 1] + 0.5 * (previous + density) * dr
            previous = density
        }
        let total = cumulative[resolution]
        var table = [Double](repeating: r0, count: count)
        var i = 0
        for k in 0..<count {
            let target = total * Double(k) / Double(count - 1)
            while i < resolution && cumulative[i + 1] < target { i += 1 }
            if i >= resolution { table[k] = r1; continue }
            let span = cumulative[i + 1] - cumulative[i]
            let t = span > 0 ? (target - cumulative[i]) / span : 0.0
            table[k] = r0 + (Double(i) + t) * dr
        }
        table[count - 1] = r1
        return table
    }

    /// Seed or respawn one particle exactly as the GPU kernel does, in double
    /// precision. Event 0 seeds from the steady profile; later events respawn
    /// into the feeding annulus.
    public static func spawn(index: UInt32, event: UInt32, seed: UInt64, inverseCdf: [Double], potential: Potential) -> ParticleState {
        let h0 = Hash.draw(seed: seed, index: index, event: event, lane: 0)
        let h1 = Hash.draw(seed: seed, index: index, event: event, lane: 1)
        let u0 = Hash.unit(h0.x), u1 = Hash.unit(h0.y), u2 = Hash.unit(h0.z), u3 = Hash.unit(h0.w)
        let u4 = Hash.unit(h1.x), u5 = Hash.unit(h1.y)
        let r: Double
        if event == 0 {
            let position = u0 * Double(inverseCdf.count - 1)
            let k = min(Int(position), inverseCdf.count - 2)
            r = inverseCdf[k] + (position - Double(k)) * (inverseCdf[k + 1] - inverseCdf[k])
        } else {
            let inner = feedInner * feedInner
            let outerSquared = outer * outer
            r = (inner + (outerSquared - inner) * u0).squareRoot()
        }
        let phi = 2.0 * Double.pi * u1
        let (g0, g1) = Hash.gaussianPair(u2, u3)
        let (g2, g3) = Hash.gaussianPair(u4, u5)
        let vc = potential.circularSpeed(r)
        let dispersion = Constants.feedVelocityDispersion.value
        let aspect = Constants.diskAspectRatio.value
        let position = SIMD3(r * cos(phi), r * sin(phi), aspect * r * g0)
        let velocity = SIMD3(-vc * sin(phi), vc * cos(phi), 0.0) + dispersion * vc * SIMD3(g1, g2, g3)
        return ParticleState(position: position, velocity: velocity)
    }

    /// A particle on a circular orbit in the equatorial plane.
    public static func circularOrbit(radius r: Double, azimuth phi: Double, potential: Potential) -> ParticleState {
        let v = potential.circularSpeed(r)
        let position = SIMD3(r * cos(phi), r * sin(phi), 0.0)
        let velocity = SIMD3(-v * sin(phi), v * cos(phi), 0.0)
        return ParticleState(position: position, velocity: velocity)
    }
}
