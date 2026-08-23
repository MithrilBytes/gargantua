/// Renders the Metal header that mirrors `Constants`. The checked in copy at
/// Sources/Gargantua/Shaders/Constants.h must equal this output; a style test
/// enforces it and `make constants` regenerates it.
public enum MetalHeader {
    public static let path = "Sources/Gargantua/Shaders/Constants.h"

    public static func render(_ entries: [any ConstantEntry] = Constants.all) -> String {
        var out = """
        // Generated from Sources/Oracle/Constants.swift. Do not edit by hand.
        // Regenerate with: make constants
        #ifndef GARGANTUA_CONSTANTS_H
        #define GARGANTUA_CONSTANTS_H


        """
        for entry in entries {
            if !entry.note.isEmpty {
                out += "// \(entry.note)\n"
            }
            out += "// Source: \(entry.source)\n"
            out += "#define \(entry.symbol) (\(entry.metalLiteral))\n\n"
        }
        out += "#endif\n"
        return out
    }
}
