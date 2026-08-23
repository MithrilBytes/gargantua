import Foundation

/// Formats the hud lines. No drawing, no measuring.
struct HudState {
    var preset: String
    var particles: Int
    var seed: UInt64
    var fps: Double
    var cpuMilliseconds: Double
    var gpuMilliseconds: Double
    var paused: Bool
    var gpuErrors: UInt64
    var validation: String
}

enum Hud {
    static func lines(_ state: HudState) -> [String] {
        let particles = NumberFormatter.localizedString(from: NSNumber(value: state.particles), number: .decimal)
        let status = state.paused ? "paused" : "running"
        return [
            "gargantua  \(state.preset)  \(particles) particles  seed \(state.seed)",
            String(format: "%.1f fps  frame %.2f ms  gpu %.2f ms  %@", state.fps, state.cpuMilliseconds, state.gpuMilliseconds, status),
            "errors \(state.gpuErrors)  validation \(state.validation)",
        ]
    }
}
