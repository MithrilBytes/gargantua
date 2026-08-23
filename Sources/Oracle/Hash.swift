import Foundation

/// Counter based hashing so every random number is a pure function of the
/// seed, the particle index and an event counter. The GPU runs the same
/// integer arithmetic, so the two sides agree bit for bit on the integers.
public enum Hash {
    /// pcg4d from Jarzynski, M. and Olano, M., 2020. Hash functions for GPU
    /// rendering. Journal of Computer Graphics Techniques 9(3), 20.
    public static func pcg4d(_ input: SIMD4<UInt32>) -> SIMD4<UInt32> {
        var v = input &* 1664525 &+ 1013904223
        v.x &+= v.y &* v.w
        v.y &+= v.z &* v.x
        v.z &+= v.x &* v.y
        v.w &+= v.y &* v.z
        v ^= v &>> 16
        v.x &+= v.y &* v.w
        v.y &+= v.z &* v.x
        v.z &+= v.x &* v.y
        v.w &+= v.y &* v.z
        return v
    }

    /// Four hashes for one (seed, index, event) triple. The lane selects a
    /// separate stream so an event can draw more than four numbers.
    public static func draw(seed: UInt64, index: UInt32, event: UInt32, lane: UInt32 = 0) -> SIMD4<UInt32> {
        let low = UInt32(truncatingIfNeeded: seed)
        let high = UInt32(truncatingIfNeeded: seed >> 32)
        return pcg4d(SIMD4(index, event, low ^ (lane &* 0x9E37_79B9), high))
    }

    /// Uniform in [0, 1) from the top 24 bits, exactly representable in single precision.
    public static func unit(_ x: UInt32) -> Double {
        Double(x >> 8) / 16_777_216.0
    }

    /// Two standard normal deviates from two uniforms.
    /// Box, G. E. P. and Muller, M. E., 1958. A note on the generation of
    /// random normal deviates. Annals of Mathematical Statistics 29, 610.
    public static func gaussianPair(_ u1: Double, _ u2: Double) -> (Double, Double) {
        let radius = (-2.0 * log(1.0 - u1)).squareRoot()
        let angle = 2.0 * Double.pi * u2
        return (radius * cos(angle), radius * sin(angle))
    }
}
