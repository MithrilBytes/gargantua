import Foundation

/// Planck emission turned into display color. Used once at launch to build
/// the color table the shaders sample.
public enum Blackbody {
    /// Second radiation constant c2 = h c / k in meter kelvin.
    /// Tiesinga, E., Mohr, P. J., Newell, D. B. and Taylor, B. N., 2021.
    /// CODATA recommended values of the fundamental physical constants: 2018.
    /// Reviews of Modern Physics 93, 025010.
    public static let c2 = 1.438776877e-2

    /// Spectral radiance up to a constant factor, wavelength in nanometers.
    public static func planck(wavelengthNm: Double, temperature: Double) -> Double {
        let lambda = wavelengthNm * 1e-9
        let exponent = c2 / (lambda * temperature)
        return 1.0 / (pow(lambda, 5.0) * (exp(exponent) - 1.0))
    }

    /// Piecewise Gaussian lobe used by the matching function fit.
    static func lobe(_ x: Double, _ mu: Double, _ sigma1: Double, _ sigma2: Double) -> Double {
        let sigma = x < mu ? sigma1 : sigma2
        let t = (x - mu) / sigma
        return exp(-0.5 * t * t)
    }

    /// CIE 1931 two degree matching functions from the multi lobe fit of
    /// Wyman, C., Sloan, P.-P. and Shirley, P., 2013. Simple analytic
    /// approximations to the CIE XYZ color matching functions. Journal of
    /// Computer Graphics Techniques 2(2), 1.
    public static func matchingFunctions(wavelengthNm x: Double) -> SIMD3<Double> {
        let xBar = 1.056 * lobe(x, 599.8, 37.9, 31.0) + 0.362 * lobe(x, 442.0, 16.0, 26.7) - 0.065 * lobe(x, 501.1, 20.4, 26.2)
        let yBar = 0.821 * lobe(x, 568.8, 46.9, 40.5) + 0.286 * lobe(x, 530.9, 16.3, 31.1)
        let zBar = 1.217 * lobe(x, 437.0, 11.8, 36.0) + 0.681 * lobe(x, 459.0, 26.0, 13.4)
        return SIMD3(xBar, yBar, zBar)
    }

    /// Tristimulus values of a blackbody, integrated over the visible band.
    public static func xyz(temperature: Double) -> SIMD3<Double> {
        var sum = SIMD3<Double>(repeating: 0.0)
        var wavelength = 380.0
        while wavelength <= 780.0 {
            sum += matchingFunctions(wavelengthNm: wavelength) * planck(wavelengthNm: wavelength, temperature: temperature)
            wavelength += 1.0
        }
        return sum
    }

    public static func chromaticity(temperature: Double) -> (x: Double, y: Double) {
        let c = xyz(temperature: temperature)
        let total = c.x + c.y + c.z
        return (c.x / total, c.y / total)
    }

    /// XYZ to linear sRGB with the D65 white point.
    /// IEC 61966-2-1:1999, Multimedia systems and equipment, colour
    /// measurement and management, part 2-1: default RGB colour space, sRGB.
    public static func linearSRGB(xyz c: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            3.2406 * c.x - 1.5372 * c.y - 0.4986 * c.z,
            -0.9689 * c.x + 1.8758 * c.y + 0.0415 * c.z,
            0.0557 * c.x - 0.2040 * c.y + 1.0570 * c.z)
    }

    /// Linear sRGB chromaticity of a blackbody, clipped to the gamut and
    /// scaled so the largest channel is one.
    public static func normalizedColor(temperature: Double) -> SIMD3<Double> {
        var rgb = linearSRGB(xyz: xyz(temperature: temperature))
        rgb = SIMD3(max(rgb.x, 0.0), max(rgb.y, 0.0), max(rgb.z, 0.0))
        let peak = max(rgb.x, max(rgb.y, rgb.z))
        return peak > 0.0 ? rgb / peak : SIMD3(repeating: 1.0)
    }

    /// Log spaced color table between two temperatures.
    public static func table(count: Int = Int(Constants.blackbodyTableSize.value),
                             minimum: Double = Constants.blackbodyMinTemperature.value,
                             maximum: Double = Constants.blackbodyMaxTemperature.value) -> [SIMD3<Double>] {
        (0..<count).map { k in
            let t = Double(k) / Double(count - 1)
            let temperature = exp(log(minimum) + t * (log(maximum) - log(minimum)))
            return normalizedColor(temperature: temperature)
        }
    }

    /// Table coordinate for a temperature, matching the shader's lookup.
    public static func tableCoordinate(temperature: Double,
                                       minimum: Double = Constants.blackbodyMinTemperature.value,
                                       maximum: Double = Constants.blackbodyMaxTemperature.value) -> Double {
        let clamped = min(max(temperature, minimum), maximum)
        return (log(clamped) - log(minimum)) / (log(maximum) - log(minimum))
    }
}
