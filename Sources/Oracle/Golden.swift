import Foundation

/// A golden is a physical claim with an expected value and a tolerance,
/// stored as data in goldens/ so the claim and its bar are reviewable.
public struct Golden: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        /// |measured - expected| / |expected| must be below tolerance.
        case relative
        /// |measured - expected| must be below tolerance.
        case absolute
        /// Two measurements must agree exactly.
        case bitwise
    }

    public let name: String
    public let claim: String
    public let kind: Kind
    public let expected: Double
    public let tolerance: Double
    public let method: String
    public let parameters: [String: Double]

    public init(name: String, claim: String, kind: Kind, expected: Double, tolerance: Double, method: String, parameters: [String: Double]) {
        self.name = name
        self.claim = claim
        self.kind = kind
        self.expected = expected
        self.tolerance = tolerance
        self.method = method
        self.parameters = parameters
    }

    public static func load(json: String) throws -> Golden {
        try JSONDecoder().decode(Golden.self, from: Data(json.utf8))
    }

    public func parameter(_ key: String) -> Double {
        guard let value = parameters[key] else {
            preconditionFailure("golden \(name) has no parameter \(key)")
        }
        return value
    }

    /// Whether a measurement meets the bar.
    public func passes(_ measured: Double) -> Bool {
        switch kind {
        case .relative: return abs(measured - expected) / abs(expected) <= tolerance
        case .absolute: return abs(measured - expected) <= tolerance
        case .bitwise: return measured == expected
        }
    }

    public var toleranceDescription: String {
        switch kind {
        case .relative: return String(format: "%.1f percent", tolerance * 100)
        case .absolute: return "\(tolerance)"
        case .bitwise: return "bitwise"
        }
    }
}
