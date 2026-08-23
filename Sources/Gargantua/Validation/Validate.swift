import Foundation
import Metal
import Oracle
import ShaderTypes

/// `gargantua validate`: runs every golden the live GPU can be held to and
/// prints a table. Exit 0 when all pass, 1 when any fails, 2 on an
/// operational error.
@MainActor
enum Validate {
    struct Row {
        let golden: Golden
        let measured: String
        let passed: Bool
    }

    static func run(_ options: Options) -> Never {
        let context = GpuContext()
        let configuration = Configuration.make(options)
        if let refusal = context.budget.refusal(bytes: configuration.bytes, describing: "Preset \(configuration.preset.rawValue)") {
            Exit.operational(refusal)
        }
        let simPass = SimPass(context: context)
        var rows: [Row] = []
        for name in ["isco", "determinism"] {
            let golden = load(name)
            switch name {
            case "isco": rows.append(isco(golden, context: context, simPass: simPass, configuration: configuration))
            case "determinism": rows.append(determinism(golden, context: context, simPass: simPass, configuration: configuration))
            default: break
            }
        }
        print(rows: rows, device: context.device.name)
        exit(rows.allSatisfy(\.passed) ? 0 : 1)
    }

    static func load(_ name: String) -> Golden {
        guard let json = EmbeddedResources.files["goldens/\(name).json"] else {
            Exit.operational("Golden \(name) is missing from the embedded resources.")
        }
        do {
            return try Golden.load(json: json)
        } catch {
            Exit.operational("Golden \(name) does not parse: \(error.localizedDescription)")
        }
    }

    /// Advance the simulation by a number of substeps, a bounded batch per
    /// command buffer so no buffer carries more than a few milliseconds.
    static func advance(_ system: ParticleSystem, steps: Int, context: GpuContext, simPass: SimPass, seedFirst: Bool) {
        var remaining = steps
        var first = seedFirst
        while remaining > 0 || first {
            let batch = min(remaining, 25)
            let commandBuffer = context.makeCommandBuffer(label: "validate batch")
            if first {
                simPass.encodeSeed(commandBuffer, system: system)
                first = false
            }
            for _ in 0..<batch { simPass.encodeStep(commandBuffer, system: system) }
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            remaining -= batch
        }
    }

    /// Copy the particle buffer to host memory.
    static func readback(_ system: ParticleSystem, context: GpuContext) -> [Particle] {
        let bytes = system.count * Int(Configuration.particleStride)
        let shared = context.makeBuffer(bytes: bytes, label: "validate readback", shared: true)
        let commandBuffer = context.makeCommandBuffer(label: "validate readback")
        guard let blit = commandBuffer.makeBlitCommandEncoder() else {
            Exit.operational("Metal could not create the readback blit encoder.")
        }
        blit.copy(from: system.buffer, sourceOffset: 0, to: shared, destinationOffset: 0, size: bytes)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return Array(UnsafeBufferPointer(start: shared.contents().bindMemory(to: Particle.self, capacity: system.count), count: system.count))
    }

    static func isco(_ golden: Golden, context: GpuContext, simPass: SimPass, configuration: Configuration) -> Row {
        let system = ParticleSystem(context: context, count: configuration.particles, seed: configuration.seed, potential: .paczynskiWiita)
        advance(system, steps: Int(golden.parameter("settlingSteps")) / Int(Constants.simulationSubsteps.value), context: context, simPass: simPass, seedFirst: true)
        let radii = readback(system, context: context).map { particle -> Double in
            let x = Double(particle.position.x), y = Double(particle.position.y)
            return (x * x + y * y).squareRoot()
        }
        let edge = DiskEdge.innerEdge(radii: radii, binWidth: golden.parameter("binWidth"),
                                      fitInner: golden.parameter("fitInner"), fitOuter: golden.parameter("fitOuter"))
        return Row(golden: golden, measured: String(format: "r = %.3f", edge), passed: golden.passes(edge))
    }

    static func determinism(_ golden: Golden, context: GpuContext, simPass: SimPass, configuration: Configuration) -> Row {
        let steps = Int(golden.parameter("steps")) / Int(Constants.simulationSubsteps.value)
        var checksums: [UInt64] = []
        for _ in 0..<2 {
            let system = ParticleSystem(context: context, count: configuration.particles, seed: configuration.seed, potential: .paczynskiWiita)
            advance(system, steps: steps, context: context, simPass: simPass, seedFirst: true)
            checksums.append(fnv1a(readback(system, context: context)))
        }
        let same = checksums[0] == checksums[1]
        return Row(golden: golden, measured: String(format: "%016llx vs %016llx", checksums[0], checksums[1]), passed: same)
    }

    /// 64 bit FNV-1a over the raw particle bytes.
    /// Fowler, G., Noll, L. C. and Vo, K.-P., 1991; Noll, L. C., FNV hash, www.isthe.com/chongo/tech/comp/fnv.
    static func fnv1a(_ particles: [Particle]) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        particles.withUnsafeBytes { bytes in
            for byte in bytes {
                hash ^= UInt64(byte)
                hash = hash &* 0x100000001b3
            }
        }
        return hash
    }

    static func print(rows: [Row], device: String) {
        Console.line("validation on \(device)")
        let nameWidth = max(rows.map { $0.golden.name.count }.max() ?? 0, 6)
        let claimWidth = rows.map { $0.golden.claim.count }.max() ?? 0
        let measuredWidth = max(rows.map { $0.measured.count }.max() ?? 0, 8)
        Console.line(pad("golden", nameWidth) + "  " + pad("claim", claimWidth) + "  " + pad("measured", measuredWidth) + "  tolerance    status")
        for row in rows {
            Console.line(pad(row.golden.name, nameWidth) + "  " + pad(row.golden.claim, claimWidth) + "  " + pad(row.measured, measuredWidth) + "  " + pad(row.golden.toleranceDescription, 11) + "  " + (row.passed ? "pass" : "FAIL"))
        }
    }

    static func pad(_ text: String, _ width: Int) -> String {
        text + String(repeating: " ", count: max(0, width - text.count))
    }
}
