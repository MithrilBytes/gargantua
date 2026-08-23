import Foundation

/// Assembles a shader translation unit from the embedded sources. Quoted
/// includes are substituted inline because the runtime compiler has no
/// include path; line directives keep compiler messages pointing at the
/// original files.
enum ShaderSource {
    static func text(_ key: String) -> String? {
        EmbeddedResources.files[key]
    }

    static func assemble(_ file: String) -> String {
        var visited: Set<String> = []
        return expand(file, visited: &visited)
    }

    static func locate(_ name: String) -> (key: String, text: String)? {
        for directory in ["Shaders", "include"] {
            let key = "\(directory)/\(name)"
            if let text = EmbeddedResources.files[key] { return (key, text) }
        }
        return nil
    }

    private static func expand(_ name: String, visited: inout Set<String>) -> String {
        guard let (key, text) = locate(name) else {
            Exit.operational("Shader source \(name) is missing from the embedded resources.")
        }
        guard !visited.contains(key) else { return "" }
        visited.insert(key)
        var out = "#line 1 \"\(name)\"\n"
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (offset, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#include \"") {
                let start = trimmed.index(trimmed.startIndex, offsetBy: 10)
                let included = String(trimmed[start...]).replacingOccurrences(of: "\"", with: "")
                out += expand(included, visited: &visited)
                out += "#line \(offset + 2) \"\(name)\"\n"
            } else {
                out += line + "\n"
            }
        }
        return out
    }

    /// Names of every embedded shader translation unit.
    static var units: [String] {
        EmbeddedResources.files.keys
            .filter { $0.hasPrefix("Shaders/") && $0.hasSuffix(".metal") }
            .map { String($0.dropFirst("Shaders/".count)) }
            .sorted()
    }
}
