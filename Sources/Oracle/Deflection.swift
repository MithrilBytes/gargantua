import Foundation

/// Azimuthal sweep of null rays outside a sphere, so the march can skip the
/// empty legs of every ray and look the rest of the bending up. A ray in
/// Schwarzschild with impact parameter b sweeps
///
///     phi = integral of b du / sqrt(1 - b^2 u^2 (1 - 2u)),  u = 1 / r
///
/// between two radii (Chandrasekhar 1983, ch. 3). The tables are plain
/// Simpson sums in double precision; nothing adaptive.
public enum Deflection {
    /// Largest impact parameter a ray moving outward at radius R can have:
    /// the tangential ray, b = R / sqrt(1 - 2 / R).
    public static func maximumImpactParameter(atRadius r: Double) -> Double {
        r / (1.0 - Constants.schwarzschildRadius.value / r).squareRoot()
    }

    /// Azimuthal sweep from radius R out to infinity along an escaping ray.
    /// The substitution u = uMax sin^2(theta) turns the inverse square root
    /// turning point of a tangential ray into a finite limit; the composite
    /// midpoint rule never evaluates the endpoints, so that limit is never
    /// needed explicitly.
    public static func sweep(fromRadius r: Double, impactParameter b: Double, intervals: Int = 2048) -> Double {
        guard b > 0.0 else { return 0.0 }
        let bound = min(b, maximumImpactParameter(atRadius: r))
        let uMax = 1.0 / r
        let h = (Double.pi / 2.0) / Double(intervals)
        var sum = 0.0
        for k in 0..<intervals {
            let theta = (Double(k) + 0.5) * h
            let s = sin(theta), c = cos(theta)
            let u = uMax * s * s
            let inner = 1.0 - bound * bound * u * u * (1.0 - 2.0 * u)
            if inner > 0.0 {
                sum += bound * 2.0 * uMax * s * c / inner.squareRoot()
            }
        }
        return sum * h
    }

    /// Tables are sampled at b = low + (high - low) (1 - (1 - t)^2) for t
    /// uniform in [0, 1], so the square root behaviour of the sweep near the
    /// tangential limit at the top of the range is resolved by linear
    /// interpolation in t.
    public static func tableImpactParameter(low: Double, high: Double, t: Double) -> Double {
        let back = 1.0 - t
        return low + (high - low) * (1.0 - back * back)
    }

    /// Inverse of `tableImpactParameter`: the table coordinate for b.
    public static func tableCoordinate(low: Double, high: Double, impactParameter b: Double) -> Double {
        let x = min(max((b - low) / (high - low), 0.0), 1.0)
        return 1.0 - (1.0 - x).squareRoot()
    }

    /// Periapsis of a ray with impact parameter b above the critical value:
    /// the smallest positive root of 1 - b^2 u^2 (1 - 2u) = 0, by Newton
    /// iteration from the flat space estimate u = 1 / b.
    public static func periapsis(impactParameter b: Double) -> Double {
        var u = 1.0 / b
        for _ in 0..<60 {
            let value = 1.0 - b * b * u * u * (1.0 - 2.0 * u)
            let slope = -b * b * (2.0 * u - 6.0 * u * u)
            let next = u - value / slope
            if abs(next - u) < 1e-15 { u = next; break }
            u = next
        }
        return 1.0 / u
    }

    /// Total sweep of a ray launched inward from radius R that turns at its
    /// periapsis and comes back out to R, for b above the critical impact
    /// parameter: twice the sweep between R and the periapsis, by symmetry.
    /// Beyond R on the way out the ray continues along the asymptote that
    /// `sweep(fromRadius:)` describes, so a ray from R to infinity sweeps
    /// this plus the sweep from R.
    public static func turningSweep(fromRadius r: Double, impactParameter b: Double, intervals: Int = 2048) -> Double {
        let peri = periapsis(impactParameter: b)
        return 2.0 * (sweep(fromRadius: peri, impactParameter: b, intervals: intervals) - sweep(fromRadius: r, impactParameter: b, intervals: intervals))
    }

    /// Sweep of a ray launched inward from radius R that turns and escapes
    /// to infinity: the turn back to R plus the outgoing leg from R.
    public static func escapeSweep(fromRadius r: Double, impactParameter b: Double, intervals: Int = 2048) -> Double {
        turningSweep(fromRadius: r, impactParameter: b, intervals: intervals) + sweep(fromRadius: r, impactParameter: b, intervals: intervals)
    }

    /// Sweep from radius R to infinity, tabulated over b in [0, bMax(R)].
    public static func sweepTable(fromRadius r: Double, count: Int, intervals: Int = 2048) -> [Double] {
        let bMax = maximumImpactParameter(atRadius: r)
        return (0..<count).map { sweep(fromRadius: r, impactParameter: tableImpactParameter(low: 0.0, high: bMax, t: Double($0) / Double(count - 1)), intervals: intervals) }
    }

    /// Total sweep of rays launched inward from the camera radius that never
    /// reach the integration sphere, tabulated over b in [bEnter, bMax(camera)].
    public static func skyTable(cameraRadius r: Double, sphereRadius: Double, count: Int, intervals: Int = 2048) -> [Double] {
        let low = maximumImpactParameter(atRadius: sphereRadius)
        let high = maximumImpactParameter(atRadius: r)
        return (0..<count).map { escapeSweep(fromRadius: r, impactParameter: tableImpactParameter(low: low, high: high, t: Double($0) / Double(count - 1)), intervals: intervals) }
    }
}
