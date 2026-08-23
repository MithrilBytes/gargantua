import Foundation

/// The oracle's picture of the disk: every pixel is a null geodesic marched
/// through a volume field with the same gather the GPU performs, in double
/// precision, one ray at a time. Slow on purpose.
public enum LensedRender {
    public struct Camera: Sendable {
        public var position: SIMD3<Double>
        public var right: SIMD3<Double>
        public var up: SIMD3<Double>
        public var forward: SIMD3<Double>
        /// tan(fov / 2), scaled by aspect in x.
        public var tanHalfFov: SIMD2<Double>

        public init(position: SIMD3<Double>, right: SIMD3<Double>, up: SIMD3<Double>, forward: SIMD3<Double>, tanHalfFov: SIMD2<Double>) {
            self.position = position
            self.right = right
            self.up = up
            self.forward = forward
            self.tanHalfFov = tanHalfFov
        }

        public func direction(pixelX: Int, pixelY: Int, width: Int, height: Int) -> SIMD3<Double> {
            let x = (2.0 * (Double(pixelX) + 0.5) / Double(width) - 1.0) * tanHalfFov.x
            let y = (1.0 - 2.0 * (Double(pixelY) + 0.5) / Double(height)) * tanHalfFov.y
            let d = forward + x * right + y * up
            return d / (d * d).sum().squareRoot()
        }
    }

    public struct Shading: Sendable {
        public var opacity: Double
        public var slabHalfHeight: Double
        public var redshift: Bool

        public init(opacity: Double = Constants.volumeOpacity.value,
                    slabHalfHeight: Double = Constants.diskSlabHalfHeight.value,
                    redshift: Bool = true) {
            self.opacity = opacity
            self.slabHalfHeight = slabHalfHeight
            self.redshift = redshift
        }
    }

    /// Linear rgb gathered along one ray, without any background.
    public static func trace(origin: SIMD3<Double>, direction: SIMD3<Double>, field: VolumeField,
                             settings: Schwarzschild.Settings, shading: Shading) -> SIMD3<Double> {
        var ray = Schwarzschild.launch(from: origin, direction: direction)
        var color = SIMD3<Double>(repeating: 0.0)
        var transmittance = 1.0
        var previous = ray.position
        for _ in 0..<settings.stepCap {
            ray.state = Schwarzschild.step(ray.state, h: settings.stepLength(at: ray.state.r))
            let position = ray.position
            if ray.state.r <= settings.captureRadius { break }
            if abs(position.z) < shading.slabHalfHeight,
               abs(position.x) < field.halfExtent, abs(position.y) < field.halfExtent,
               transmittance > 0.004 {
                let s = field.sample(at: position)
                if s.density > 0.0 {
                    let pathLength = ((position - previous) * (position - previous)).sum().squareRoot()
                    var g3 = 1.0
                    if shading.redshift {
                        let g = Schwarzschild.redshiftFactor(radius: ray.state.r, direction: ray.direction, gas: s.velocity)
                        g3 = g * g * g
                    }
                    let alpha = 1.0 - exp(-shading.opacity * s.density * pathLength)
                    color += transmittance * s.emission * g3 * pathLength
                    transmittance *= 1.0 - alpha
                }
            }
            previous = position
            if ray.state.r >= settings.escapeRadius { break }
        }
        return color
    }

    /// Per pixel linear rgb, row major.
    public static func image(width: Int, height: Int, camera: Camera, field: VolumeField,
                             settings: Schwarzschild.Settings, shading: Shading = Shading()) -> [SIMD3<Double>] {
        var pixels = [SIMD3<Double>](repeating: SIMD3(repeating: 0.0), count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let d = camera.direction(pixelX: x, pixelY: y, width: width, height: height)
                pixels[y * width + x] = trace(origin: camera.position, direction: d, field: field, settings: settings, shading: shading)
            }
        }
        return pixels
    }

    /// Rec. 709 luma. ITU-R BT.709-6, 2015, item 3.3.
    public static func luminance(_ rgb: SIMD3<Double>) -> Double {
        0.2126 * rgb.x + 0.7152 * rgb.y + 0.0722 * rgb.z
    }

    /// Brightness of the brighter half of the image over the dimmer half,
    /// split at the column through the hole.
    public static func sideRatio(luminance: [Double], width: Int, height: Int) -> Double {
        var left = 0.0, right = 0.0
        for y in 0..<height {
            for x in 0..<width {
                if x < width / 2 { left += luminance[y * width + x] } else { right += luminance[y * width + x] }
            }
        }
        let high = max(left, right), low = min(left, right)
        return low > 0.0 ? high / low : .infinity
    }
}
