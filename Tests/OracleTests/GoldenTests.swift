import Testing
import Foundation
import Oracle

/// The golden definitions, checked against the oracle. The GPU is held to
/// the same files by `gargantua validate`.
enum Goldens {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "goldens")

    static func load(_ name: String) throws -> Golden {
        try Golden.load(json: String(contentsOf: directory.appending(path: "\(name).json"), encoding: .utf8))
    }
}

@Suite struct GoldenDefinitions {
    @Test func everyGoldenParses() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: Goldens.directory.path).filter { $0.hasSuffix(".json") }
        #expect(!files.isEmpty)
        for file in files {
            let golden = try Goldens.load(String(file.dropLast(5)))
            #expect(golden.name + ".json" == file)
            #expect(!golden.claim.isEmpty && !golden.method.isEmpty)
        }
    }

    @Test func toleranceSemantics() throws {
        let golden = try Goldens.load("isco")
        #expect(golden.passes(6.29))
        #expect(!golden.passes(6.31))
        #expect(golden.passes(5.71))
    }
}

@Suite struct IscoGolden {
    /// The oracle disk, seeded and respawned exactly like the kernel, must
    /// settle to the same inner edge the GPU is held to.
    @Test func oracleDiskSettlesToAnInnerEdgeAtIsco() throws {
        let golden = try Goldens.load("isco")
        let potential = Potential.paczynskiWiita
        let dynamics = ParticleDynamics(potential: potential)
        let table = DiskModel.radialInverseCdf(count: 1024)
        let seed: UInt64 = 11
        let count: UInt32 = 24_000
        var particles = (0..<count).map { DiskModel.spawn(index: $0, event: 0, seed: seed, inverseCdf: table, potential: potential) }
        var respawns = [UInt32](repeating: 0, count: Int(count))
        for _ in 0..<Int(golden.parameter("settlingSteps")) {
            for i in 0..<Int(count) {
                let before = particles[i].position
                dynamics.step(&particles[i])
                if ParticleDynamics.removed(before: before, after: particles[i]) {
                    respawns[i] += 1
                    particles[i] = DiskModel.spawn(index: UInt32(i), event: respawns[i], seed: seed, inverseCdf: table, potential: potential)
                }
            }
        }
        let edge = DiskEdge.innerEdge(radii: particles.map(\.cylindricalRadius),
                                      binWidth: golden.parameter("binWidth"),
                                      fitInner: golden.parameter("fitInner"),
                                      fitOuter: golden.parameter("fitOuter"))
        #expect(golden.passes(edge), "inner edge measured at \(edge)")
        #expect(respawns.reduce(0, +) > 0)
    }

    @Test func edgeMeasurementRecoversAnAnalyticProfile() {
        var radii: [Double] = []
        let table = DiskModel.radialInverseCdf(count: 4096)
        for i in 0..<400_000 {
            let u = Hash.unit(Hash.draw(seed: 5, index: UInt32(i), event: 0).x)
            let position = u * Double(table.count - 1)
            let k = min(Int(position), table.count - 2)
            radii.append(table[k] + (position - Double(k)) * (table[k + 1] - table[k]))
        }
        let edge = DiskEdge.innerEdge(radii: radii, binWidth: 0.25, fitInner: 6.5, fitOuter: 9.0)
        #expect(abs(edge - 6.0) < 0.1, "edge \(edge)")
    }
}
