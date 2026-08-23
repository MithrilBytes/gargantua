import Foundation

/// A resolved emission and velocity volume in host memory, sampled the way
/// the march kernel samples its textures: trilinear filtering on normalized
/// coordinates with texel centers at half steps, zero outside the cube.
public struct VolumeField: Sendable {
    public struct Sample: Sendable, Equatable {
        public var emission: SIMD3<Double>
        public var density: Double
        public var velocity: SIMD3<Double>
    }

    public let size: Int
    public let halfExtent: Double
    /// Per voxel emission rgb and density in w, x fastest.
    public let emission: [SIMD4<Double>]
    /// Per voxel mean velocity.
    public let velocity: [SIMD3<Double>]

    public init(size: Int, halfExtent: Double, emission: [SIMD4<Double>], velocity: [SIMD3<Double>]) {
        precondition(emission.count == size * size * size && velocity.count == emission.count)
        self.size = size
        self.halfExtent = halfExtent
        self.emission = emission
        self.velocity = velocity
    }

    public func index(_ x: Int, _ y: Int, _ z: Int) -> Int {
        (z * size + y) * size + x
    }

    func texel(_ x: Int, _ y: Int, _ z: Int) -> (SIMD4<Double>, SIMD3<Double>) {
        guard x >= 0, y >= 0, z >= 0, x < size, y < size, z < size else {
            return (SIMD4(repeating: 0.0), SIMD3(repeating: 0.0))
        }
        let i = index(x, y, z)
        return (emission[i], velocity[i])
    }

    public func sample(at position: SIMD3<Double>) -> Sample {
        let unit = (position + halfExtent) / (2.0 * halfExtent)
        let t = unit * Double(size) - 0.5
        let base = SIMD3(floor(t.x), floor(t.y), floor(t.z))
        let frac = t - base
        let x0 = Int(base.x), y0 = Int(base.y), z0 = Int(base.z)
        var e = SIMD4<Double>(repeating: 0.0)
        var v = SIMD3<Double>(repeating: 0.0)
        for dz in 0...1 {
            let wz = dz == 0 ? 1.0 - frac.z : frac.z
            for dy in 0...1 {
                let wy = dy == 0 ? 1.0 - frac.y : frac.y
                for dx in 0...1 {
                    let wx = dx == 0 ? 1.0 - frac.x : frac.x
                    let w = wx * wy * wz
                    if w == 0.0 { continue }
                    let (te, tv) = texel(x0 + dx, y0 + dy, z0 + dz)
                    e += te * w
                    v += tv * w
                }
            }
        }
        return Sample(emission: SIMD3(e.x, e.y, e.z), density: e.w, velocity: v)
    }
}
