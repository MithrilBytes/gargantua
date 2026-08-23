import Foundation

/// Measures where the disk's surface density inner edge sits. The steady
/// profile is Sigma(r) r^(3/2) proportional to (r - r_edge), so a straight
/// line fitted through the binned, weighted counts and extrapolated to zero
/// reports the edge. Shared by the oracle test and the GPU validation.
public enum DiskEdge {
    public struct Bin: Sendable, Equatable {
        public let center: Double
        public let surfaceDensity: Double
    }

    /// Surface density estimate per radial bin, count / (2 pi r dr).
    public static func bins(radii: [Double], binWidth: Double, from start: Double, to end: Double) -> [Bin] {
        let count = Int(((end - start) / binWidth).rounded())
        var counts = [Double](repeating: 0.0, count: count)
        for r in radii where r >= start && r < end {
            counts[min(Int((r - start) / binWidth), count - 1)] += 1.0
        }
        return (0..<count).map { k in
            let center = start + (Double(k) + 0.5) * binWidth
            return Bin(center: center, surfaceDensity: counts[k] / (2.0 * Double.pi * center * binWidth))
        }
    }

    /// Inner edge from a least squares line through Sigma r^(3/2) on the fit
    /// window, extrapolated to zero.
    public static func innerEdge(radii: [Double], binWidth: Double, fitInner: Double, fitOuter: Double) -> Double {
        let all = bins(radii: radii, binWidth: binWidth, from: fitInner, to: fitOuter)
        var sumX = 0.0, sumY = 0.0, sumXX = 0.0, sumXY = 0.0
        let n = Double(all.count)
        for bin in all {
            let x = bin.center
            let y = bin.surfaceDensity * pow(bin.center, 1.5)
            sumX += x
            sumY += y
            sumXX += x * x
            sumXY += x * y
        }
        let slope = (n * sumXY - sumX * sumY) / (n * sumXX - sumX * sumX)
        let intercept = (sumY - slope * sumX) / n
        return -intercept / slope
    }
}
