import Testing
import Foundation
import Oracle

/// Repository rule enforcement. These tests read the source tree directly.
enum Repo {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let skippedDirectories: Set<String> = [".git", ".build", ".swiftpm", "Gargantua.app"]
    static let textExtensions: Set<String> = ["swift", "metal", "h", "c", "md", "yml", "yaml", "json", "txt", "sh", ""]

    static func textFiles() -> [URL] {
        var files: [URL] = []
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey])!
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                if skippedDirectories.contains(url.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }
            guard values?.isRegularFile == true, textExtensions.contains(url.pathExtension) else { continue }
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    static func read(_ relative: String) -> String? {
        try? String(contentsOf: root.appending(path: relative), encoding: .utf8)
    }

    static func swiftFiles(under relative: String) -> [URL] {
        textFiles().filter { $0.path.contains("/\(relative)/") && $0.pathExtension == "swift" }
    }
}

@Suite struct RepositoryRules {
    @Test func noEmDashOrEnDashAnywhere() {
        var offenders: [String] = []
        for file in Repo.textFiles() {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains("\u{2013}") || line.contains("\u{2014}") {
                offenders.append("\(file.path.replacingOccurrences(of: Repo.root.path, with: "")):\(number + 1)")
            }
        }
        #expect(offenders.isEmpty, Comment(rawValue: offenders.joined(separator: "\n")))
    }

    @Test func metalConstantsHeaderMatchesTheSwiftSourceOfTruth() {
        let checkedIn = Repo.read(MetalHeader.path)
        #expect(checkedIn != nil, "missing \(MetalHeader.path), run make constants")
        #expect(checkedIn == MetalHeader.render(), "\(MetalHeader.path) is stale, run make constants")
    }

    @Test func oracleNeverImportsMetal() {
        for file in Repo.swiftFiles(under: "Sources/Oracle") {
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            #expect(!text.contains("import Metal"), Comment(rawValue: file.lastPathComponent))
        }
    }

    @Test func passesComputeAndDoNotPresent() {
        for file in Repo.swiftFiles(under: "Sources/Gargantua/Passes") {
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            #expect(!text.contains("import AppKit"), Comment(rawValue: file.lastPathComponent))
        }
    }

    @Test func hudFormatsAndDoesNotDraw() {
        if let text = Repo.read("Sources/Gargantua/Hud.swift") {
            #expect(!text.contains("import Metal"))
            #expect(!text.contains("import AppKit"))
        }
    }

    @Test func everyShaderLoopNamesItsCap() {
        for file in Repo.textFiles() where file.pathExtension == "metal" {
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            for line in text.split(separator: "\n") where line.contains("for (") || line.contains("while (") {
                let capped = line.contains("_CAP") || line.contains("SIM_SUBSTEPS") || line.contains("BAKE_SAMPLES") || line.contains("BLACKBODY_TABLE_SIZE")
                #expect(capped, Comment(rawValue: "\(file.lastPathComponent): \(line.trimmingCharacters(in: .whitespaces))"))
            }
        }
    }
}
