import Foundation
import Oracle

/// Everything the renderer needs to size its resources, resolved from the
/// preset and any command line overrides.
struct Configuration: Sendable {
    var preset: Preset
    var particles: Int
    var volume: Int
    var marchWidth: Int
    var marchHeight: Int
    var seed: UInt64
    var strategy: Strategy
    var fpsCap: Int
    var upscale: Bool

    static func make(_ options: Options) -> Configuration {
        let preset = options.preset
        return Configuration(
            preset: preset,
            particles: options.particles ?? preset.particles,
            volume: options.volume ?? preset.volume,
            marchWidth: preset.marchSize.width,
            marchHeight: preset.marchSize.height,
            seed: options.seed,
            strategy: options.strategy,
            fpsCap: options.fpsCap,
            upscale: options.upscale)
    }

    /// Switch preset in place, keeping seed, strategy and cap.
    func with(preset: Preset) -> Configuration {
        var next = self
        next.preset = preset
        next.particles = preset.particles
        next.volume = preset.volume
        next.marchWidth = preset.marchSize.width
        next.marchHeight = preset.marchSize.height
        return next
    }

    static let particleStride: UInt64 = 32
    static let inverseCdfCount = 1024

    /// Named allocations the configuration implies, before any are made.
    var allocations: [(name: String, bytes: UInt64)] {
        let voxels = UInt64(volume) * UInt64(volume) * UInt64(volume)
        let pixels = UInt64(marchWidth) * UInt64(marchHeight)
        return [
            ("particles", UInt64(particles) * Configuration.particleStride),
            ("seeding table", UInt64(Configuration.inverseCdfCount) * 4),
            ("blackbody table", UInt64(Constants.blackbodyTableSize.value) * 8),
            ("volume sums", voxels * 7 * 4),
            ("emission volume", voxels * 8),
            ("velocity volume", voxels * 8),
            ("march target", pixels * 8),
            ("debug target", pixels * 8),
            ("depth and motion", pixels * 8),
            ("bake samples", strategy == .bake ? pixels * UInt64(Constants.bakeSamples.value) * 8 : 0),
            ("bake headers", strategy == .bake ? pixels * 16 : 0),
        ]
    }

    var bytes: UInt64 {
        allocations.reduce(0) { $0 + $1.bytes }
    }
}

extension Preset {
    var particles: Int {
        switch self {
        case .small: return 250_000
        case .standard: return 1_000_000
        case .max: return 4_000_000
        }
    }

    var volume: Int {
        switch self {
        case .small: return 96
        case .standard: return 128
        case .max: return 256
        }
    }

    var marchSize: (width: Int, height: Int) {
        switch self {
        case .small: return (640, 360)
        case .standard, .max: return (960, 540)
        }
    }

    /// The largest preset runs only when asked for on the command line.
    var gated: Bool { self == .max }

    var thermalNote: String {
        "The max preset holds the GPU at full load for as long as it runs; fanless machines will throttle within minutes and the frame counter will show it."
    }
}

func formatBytes(_ bytes: UInt64) -> String {
    let value = Double(bytes)
    if value >= 1e9 { return String(format: "%.1f GB", value / 1e9) }
    if value >= 1e6 { return String(format: "%.0f MB", value / 1e6) }
    if value >= 1e3 { return String(format: "%.0f kB", value / 1e3) }
    return "\(bytes) bytes"
}
