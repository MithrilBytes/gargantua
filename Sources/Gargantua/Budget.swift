import Metal
import Oracle

/// Memory is budgeted before it is allocated. The limit is the smaller of a
/// fraction of the device's recommended working set and an absolute cap.
struct MemoryBudget: Sendable {
    let recommended: UInt64
    let limit: UInt64

    init(device: MTLDevice) {
        recommended = device.recommendedMaxWorkingSetSize
        let fraction = UInt64(Double(recommended) * Constants.memoryBudgetFraction.value)
        limit = min(fraction, UInt64(Constants.memoryBudgetCapBytes.value))
    }

    /// One sentence explaining the refusal, or nil when the request fits.
    func refusal(bytes: UInt64, describing what: String) -> String? {
        guard bytes > limit else { return nil }
        let percent = Int(Constants.memoryBudgetFraction.value * 100)
        return "\(what) needs \(formatBytes(bytes)) but this machine's budget is \(formatBytes(limit)), \(percent) percent of its \(formatBytes(recommended)) working set capped at \(formatBytes(UInt64(Constants.memoryBudgetCapBytes.value)))."
    }
}
