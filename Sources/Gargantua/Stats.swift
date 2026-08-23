import Foundation

/// Frame timing measurement. Pure bookkeeping; the hud formats it and the
/// soak harness summarizes it.
struct FrameStats {
    var frames: UInt64 = 0
    var gpuErrors: UInt64 = 0
    var lastCpuInterval: Double = 0
    var lastGpuSeconds: Double = 0
    var fpsWindowStart: Double = 0
    var fpsWindowFrames: Int = 0
    var fps: Double = 0
    var gpuWindowMax: Double = 0
    var gpuDisplayed: Double = 0
    private(set) var intervals: [Double] = []
    private(set) var gpuTimes: [Double] = []
    var recording = false

    mutating func recordFrame(now: Double, previous: Double?) {
        frames += 1
        if let previous {
            lastCpuInterval = now - previous
            if recording { intervals.append(lastCpuInterval) }
        }
        if fpsWindowStart == 0 { fpsWindowStart = now }
        fpsWindowFrames += 1
        if now - fpsWindowStart >= 0.5 {
            fps = Double(fpsWindowFrames) / (now - fpsWindowStart)
            fpsWindowStart = now
            fpsWindowFrames = 0
            gpuDisplayed = gpuWindowMax
            gpuWindowMax = 0
        }
    }

    mutating func recordGpu(seconds: Double) {
        lastGpuSeconds = seconds
        gpuWindowMax = max(gpuWindowMax, seconds)
        if recording { gpuTimes.append(seconds) }
    }

    /// Summary of a recorded run, one value per line, for the soak harness.
    func summary(seconds: Double, targetFps: Int) -> [String] {
        let sorted = intervals.sorted()
        func percentile(_ p: Double) -> Double {
            guard !sorted.isEmpty else { return 0 }
            let index = min(Int(Double(sorted.count - 1) * p), sorted.count - 1)
            return sorted[index]
        }
        let budget = 1.0 / Double(targetFps)
        let late = intervals.filter { $0 > budget * 1.5 }.count
        let meanFps = intervals.isEmpty ? 0 : Double(intervals.count) / intervals.reduce(0, +)
        let gpuMean = gpuTimes.isEmpty ? 0 : gpuTimes.reduce(0, +) / Double(gpuTimes.count)
        let gpuMax = gpuTimes.max() ?? 0
        return [
            String(format: "frames %d in %.1f s", intervals.count, seconds),
            String(format: "mean fps %.1f", meanFps),
            String(format: "frame interval p50 %.2f ms, p99 %.2f ms, max %.2f ms", percentile(0.5) * 1000, percentile(0.99) * 1000, (sorted.last ?? 0) * 1000),
            String(format: "frames later than 1.5 x budget: %d", late),
            String(format: "gpu time mean %.2f ms, max %.2f ms", gpuMean * 1000, gpuMax * 1000),
            "command buffer errors \(gpuErrors)",
        ]
    }
}
