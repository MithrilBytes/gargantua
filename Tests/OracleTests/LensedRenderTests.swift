import Testing
import Foundation
import Oracle

/// A thin analytic disk as a volume field: circular Paczynski and Wiita
/// motion, thin disk temperature, Planck color.
enum SyntheticDisk {
    static func field(size: Int, moving: Bool) -> VolumeField {
        let half = Constants.volumeHalfExtent.value
        let voxel = 2.0 * half / Double(size)
        var emission = [SIMD4<Double>](repeating: SIMD4(repeating: 0.0), count: size * size * size)
        var velocity = [SIMD3<Double>](repeating: SIMD3(repeating: 0.0), count: emission.count)
        for z in 0..<size {
            for y in 0..<size {
                for x in 0..<size {
                    let px = (Double(x) + 0.5) * voxel - half
                    let py = (Double(y) + 0.5) * voxel - half
                    let pz = (Double(z) + 0.5) * voxel - half
                    let p = SIMD3(px, py, pz)
                    let r = (p.x * p.x + p.y * p.y).squareRoot()
                    guard r > 6.0, r < 24.0, abs(p.z) < 0.75 else { continue }
                    let t = DiskModel.temperature(radius: r)
                    let relative = t / Constants.peakTemperature.value
                    let color = Blackbody.normalizedColor(temperature: t)
                    let i = (z * size + y) * size + x
                    emission[i] = SIMD4(color.x, color.y, color.z, 1.0) * pow(relative, 4.0)
                    emission[i].w = 1.0
                    if moving {
                        let v = Potential.paczynskiWiita.circularSpeed(r)
                        velocity[i] = SIMD3(-v * p.y / r, v * p.x / r, 0.0)
                    }
                }
            }
        }
        return VolumeField(size: size, halfExtent: half, emission: emission, velocity: velocity)
    }

    static var camera: LensedRender.Camera {
        let elevation = 0.32, azimuth = 0.6, distance = 52.0
        let px = distance * cos(elevation) * cos(azimuth)
        let py = distance * cos(elevation) * sin(azimuth)
        let pz = distance * sin(elevation)
        let position = SIMD3(px, py, pz)
        let forward = -position / distance
        var right = SIMD3(forward.y * 1.0 - forward.z * 0.0, forward.z * 0.0 - forward.x * 1.0, 0.0)
        right /= (right * right).sum().squareRoot()
        let up = SIMD3(right.y * forward.z - right.z * forward.y, right.z * forward.x - right.x * forward.z, right.x * forward.y - right.y * forward.x)
        let tanHalf = tan(50.0 * Double.pi / 360.0)
        return LensedRender.Camera(position: position, right: right, up: up, forward: forward, tanHalfFov: SIMD2(tanHalf * 16.0 / 9.0, tanHalf))
    }
}

@Suite struct VolumeFieldTests {
    @Test func samplingHitsTexelCentersExactlyAndIsZeroOutside() {
        let size = 4
        var emission = [SIMD4<Double>](repeating: SIMD4(repeating: 0.0), count: 64)
        let velocity = [SIMD3<Double>](repeating: SIMD3(1.0, 2.0, 3.0), count: 64)
        emission[(1 * 4 + 2) * 4 + 3] = SIMD4(5.0, 6.0, 7.0, 8.0)
        let field = VolumeField(size: size, halfExtent: 2.0, emission: emission, velocity: velocity)
        let voxel = 1.0
        let center = SIMD3(3.5, 2.5, 1.5) * voxel - 2.0
        let s = field.sample(at: center)
        #expect(s.emission == SIMD3(5.0, 6.0, 7.0) && s.density == 8.0)
        #expect(s.velocity == SIMD3(1.0, 2.0, 3.0))
        let between = field.sample(at: center - SIMD3(0.5, 0.0, 0.0))
        #expect(abs(between.density - 4.0) < 1e-12)
        let outside = field.sample(at: SIMD3(3.0, 0.0, 0.0))
        #expect(outside.density == 0.0 && outside.velocity == SIMD3(repeating: 0.0))
    }
}

@Suite struct LensedRenderTests {
    @Test func staticDiskIsMirrorSymmetricAndMovingDiskIsBeamed() {
        let width = 64, height = 36
        let still = SyntheticDisk.field(size: 60, moving: false)
        let staticImage = LensedRender.image(width: width, height: height, camera: SyntheticDisk.camera, field: still, settings: .still)
        let staticRatio = LensedRender.sideRatio(luminance: staticImage.map(LensedRender.luminance), width: width, height: height)
        #expect(abs(staticRatio - 1.0) < 0.05, "static ratio \(staticRatio)")
        #expect(staticImage.map(LensedRender.luminance).reduce(0, +) > 0)

        let moving = SyntheticDisk.field(size: 60, moving: true)
        let movingImage = LensedRender.image(width: width, height: height, camera: SyntheticDisk.camera, field: moving, settings: .still)
        let movingRatio = LensedRender.sideRatio(luminance: movingImage.map(LensedRender.luminance), width: width, height: height)
        #expect(movingRatio > 1.3, "moving ratio \(movingRatio)")
    }

    @Test func redshiftFactorHasTheRightLimits() {
        let far = Schwarzschild.redshiftFactor(radius: 1e6, direction: SIMD3(1.0, 0.0, 0.0), gas: SIMD3(repeating: 0.0))
        #expect(abs(far - 1.0) < 1e-5)
        let staticNearHorizon = Schwarzschild.redshiftFactor(radius: 2.5, direction: SIMD3(1.0, 0.0, 0.0), gas: SIMD3(repeating: 0.0))
        #expect(abs(staticNearHorizon - (1.0 - 2.0 / 2.5).squareRoot()) < 1e-12)
        let approaching = Schwarzschild.redshiftFactor(radius: 1e6, direction: SIMD3(1.0, 0.0, 0.0), gas: SIMD3(-0.3, 0.0, 0.0))
        let receding = Schwarzschild.redshiftFactor(radius: 1e6, direction: SIMD3(1.0, 0.0, 0.0), gas: SIMD3(0.3, 0.0, 0.0))
        #expect(approaching > 1.0 && receding < 1.0)
        let ceiling = Constants.gasSpeedCeiling.value
        let fast = Schwarzschild.redshiftFactor(radius: 1e6, direction: SIMD3(1.0, 0.0, 0.0), gas: SIMD3(-5.0, 0.0, 0.0))
        #expect(fast < (1.0 + ceiling) / (1.0 - ceiling).squareRoot() * 1.0001 && fast.isFinite)
    }
}
