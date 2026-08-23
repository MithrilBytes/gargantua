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

    static let order = ["isco", "determinism", "shadow", "deflection", "conservation_interactive", "conservation_still", "parity", "beaming"]

    static func run(_ options: Options) -> Never {
        let context = GpuContext()
        let configuration = Configuration.make(options)
        if let refusal = context.budget.refusal(bytes: configuration.bytes, describing: "Preset \(configuration.preset.rawValue)") {
            Exit.operational(refusal)
        }
        let simPass = SimPass(context: context)
        let splatPass = SplatPass(context: context)
        let marchPass = MarchPass(context: context)
        let volume = Volume(context: context, size: configuration.volume)
        let system = ParticleSystem(context: context, count: configuration.particles, seed: configuration.seed, potential: .paczynskiWiita)
        let probes = Probes(context: context, marchPass: marchPass, volume: volume, blackbody: system.blackbody)
        let isco = load("isco")
        advance(system, steps: Int(isco.parameter("settlingSteps")) / Int(Constants.simulationSubsteps.value), context: context, simPass: simPass, seedFirst: true)

        var rows: [Row] = []
        for name in order {
            let golden = load(name)
            switch name {
            case "isco": rows.append(Validate.isco(golden, context: context, system: system))
            case "determinism": rows.append(determinism(golden, context: context, simPass: simPass, configuration: configuration))
            case "shadow": rows.append(shadow(golden, probes: probes))
            case "deflection": rows.append(deflection(golden, probes: probes))
            case "conservation_interactive": rows.append(conservation(golden, probes: probes, settings: .interactive))
            case "conservation_still": rows.append(conservation(golden, probes: probes, settings: .still))
            case "parity": rows.append(parity(golden, probes: probes))
            case "beaming": rows.append(beaming(golden, context: context, system: system, volume: volume, splatPass: splatPass, marchPass: marchPass))
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

    /// Advance the simulation by a number of step dispatches, a bounded batch
    /// per command buffer so no buffer carries more than a few milliseconds.
    static func advance(_ system: ParticleSystem, steps: Int, context: GpuContext, simPass: SimPass, seedFirst: Bool) {
        var remaining = steps
        var first = seedFirst
        while remaining > 0 || first {
            let batch = min(remaining, 25)
            let commandBuffer = context.makeCommandBuffer(label: "advance")
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
        let shared = context.makeBuffer(bytes: bytes, label: "particle readback", shared: true)
        let commandBuffer = context.makeCommandBuffer(label: "particle readback")
        guard let blit = commandBuffer.makeBlitCommandEncoder() else {
            Exit.operational("Metal could not create the readback blit encoder.")
        }
        blit.copy(from: system.buffer, sourceOffset: 0, to: shared, destinationOffset: 0, size: bytes)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return Array(UnsafeBufferPointer(start: shared.contents().bindMemory(to: Particle.self, capacity: system.count), count: system.count))
    }

    static func isco(_ golden: Golden, context: GpuContext, system: ParticleSystem) -> Row {
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

    /// Parallel bisection of the capture boundary in impact parameter.
    static func shadow(_ golden: Golden, probes: Probes) -> Row {
        var low = golden.parameter("bracketLow")
        var high = golden.parameter("bracketHigh")
        let radius = golden.parameter("launchRadius")
        let n = Int(golden.parameter("raysPerRound"))
        var measured: Double?
        rounds: for _ in 0..<Int(golden.parameter("rounds")) {
            let values = (0..<n).map { low + (high - low) * (Double($0) + 0.5) / Double(n) }
            let results = probes.run(values.map { Probes.aimed(radius: radius, impactParameter: $0) }, settings: .still)
            if let exhausted = results.firstIndex(where: { $0.outcome == RayExhausted }) {
                measured = values[exhausted]
                break rounds
            }
            let firstEscaped = results.firstIndex(where: { $0.outcome == RayEscaped }) ?? n
            let newLow = firstEscaped > 0 ? values[firstEscaped - 1] : low
            let newHigh = firstEscaped < n ? values[firstEscaped] : high
            low = newLow
            high = newHigh
        }
        let critical = measured ?? 0.5 * (low + high)
        return Row(golden: golden, measured: String(format: "b = %.4f", critical), passed: golden.passes(critical))
    }

    static func deflection(_ golden: Golden, probes: Probes) -> Row {
        let radius = golden.parameter("launchRadius")
        let b = golden.parameter("impactParameter")
        var settings = Schwarzschild.Settings.still
        settings.stepMax = .infinity
        settings.escapeRadius = radius
        let launch = Probes.aimed(radius: radius, impactParameter: b)
        let result = probes.run([launch], settings: settings)[0]
        let a = launch.direction
        let d = result.direction
        let final = SIMD3(Double(d.x), Double(d.y), Double(d.z))
        let cross = SIMD3(a.y * final.z - a.z * final.y, a.z * final.x - a.x * final.z, a.x * final.y - a.y * final.x)
        let angle = atan2((cross * cross).sum().squareRoot(), (a * final).sum())
        let note = result.outcome == RayEscaped ? "" : " (ray did not escape)"
        return Row(golden: golden, measured: String(format: "%.6f rad%@", angle, note), passed: golden.passes(angle) && result.outcome == RayEscaped)
    }

    static func conservation(_ golden: Golden, probes: Probes, settings: Schwarzschild.Settings) -> Row {
        let preset = Preset.standard.marchSize
        let launches = Probes.cameraGrid(camera: OrbitCamera(), columns: Int(golden.parameter("columns")), rows: Int(golden.parameter("rows")),
                                         aspect: Double(preset.width) / Double(preset.height))
        let results = probes.run(launches, settings: settings)
        let worst = results.map { Double($0.drift) }.max() ?? 0
        let exhausted = results.filter { $0.outcome == RayExhausted }.count
        return Row(golden: golden, measured: String(format: "max drift %.2e, %d of %d rays exhausted", worst, exhausted, results.count), passed: golden.passes(worst))
    }

    /// The same launches on both sides, from identical single precision values.
    static func parity(_ golden: Golden, probes: Probes) -> Row {
        let preset = Preset.standard.marchSize
        let launches = Probes.cameraGrid(camera: OrbitCamera(), columns: Int(golden.parameter("columns")), rows: Int(golden.parameter("rows")),
                                         aspect: Double(preset.width) / Double(preset.height)).map { launch in
            Probes.Launch(origin: SIMD3(Double(Float(launch.origin.x)), Double(Float(launch.origin.y)), Double(Float(launch.origin.z))),
                          direction: SIMD3(Double(Float(launch.direction.x)), Double(Float(launch.direction.y)), Double(Float(launch.direction.z))))
        }
        let gpu = probes.run(launches, settings: .still)
        var worst = 0.0
        var mismatchedOutcomes = 0
        for (launch, result) in zip(launches, gpu) {
            let oracle = Schwarzschild.integrate(Schwarzschild.launch(from: launch.origin, direction: launch.direction), settings: .still)
            let expected = oracle.ray.position
            let actual = SIMD3(Double(result.position.x), Double(result.position.y), Double(result.position.z))
            let distance = ((expected - actual) * (expected - actual)).sum().squareRoot()
            worst = max(worst, distance / max((expected * expected).sum().squareRoot(), 1.0))
            let outcome: Schwarzschild.Outcome = result.outcome == RayCaptured ? .captured : (result.outcome == RayEscaped ? .escaped : .exhausted)
            if outcome != oracle.outcome { mismatchedOutcomes += 1 }
        }
        return Row(golden: golden, measured: String(format: "max relative endpoint error %.2e, %d outcome mismatches", worst, mismatchedOutcomes),
                   passed: golden.passes(worst) && mismatchedOutcomes == 0)
    }

    /// Read a 3D half precision texture back as doubles.
    static func readVolume(_ texture: MTLTexture, context: GpuContext) -> [SIMD4<Double>] {
        let size = texture.width
        let bytesPerRow = size * 8
        let bytesPerImage = bytesPerRow * size
        let buffer = context.makeBuffer(bytes: bytesPerImage * size, label: "volume readback", shared: true)
        let commandBuffer = context.makeCommandBuffer(label: "volume readback")
        guard let blit = commandBuffer.makeBlitCommandEncoder() else {
            Exit.operational("Metal could not create the volume readback encoder.")
        }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: size, height: size, depth: size),
                  to: buffer, destinationOffset: 0, destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: bytesPerImage)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let count = size * size * size
        let halves = UnsafeBufferPointer(start: buffer.contents().bindMemory(to: Float16.self, capacity: count * 4), count: count * 4)
        var voxels = [SIMD4<Double>](repeating: SIMD4(repeating: 0.0), count: count)
        for i in 0..<count {
            let x = Double(halves[4 * i])
            let y = Double(halves[4 * i + 1])
            let z = Double(halves[4 * i + 2])
            let w = Double(halves[4 * i + 3])
            voxels[i] = SIMD4(x, y, z, w)
        }
        return voxels
    }

    /// Read a 2D half precision image back as linear rgb.
    static func readImage(_ texture: MTLTexture, context: GpuContext) -> [SIMD3<Double>] {
        let width = texture.width, height = texture.height
        let buffer = context.makeBuffer(bytes: width * height * 8, label: "image readback", shared: true)
        let commandBuffer = context.makeCommandBuffer(label: "image readback")
        guard let blit = commandBuffer.makeBlitCommandEncoder() else {
            Exit.operational("Metal could not create the image readback encoder.")
        }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: buffer, destinationOffset: 0, destinationBytesPerRow: width * 8, destinationBytesPerImage: width * height * 8)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let count = width * height
        let halves = UnsafeBufferPointer(start: buffer.contents().bindMemory(to: Float16.self, capacity: count * 4), count: count * 4)
        var pixels = [SIMD3<Double>](repeating: SIMD3(repeating: 0.0), count: count)
        for i in 0..<count {
            let r = Double(halves[4 * i])
            let g = Double(halves[4 * i + 1])
            let b = Double(halves[4 * i + 2])
            pixels[i] = SIMD3(r, g, b)
        }
        return pixels
    }

    /// GPU render and oracle render of the same volume, compared by the
    /// brightness ratio of the two image halves.
    static func beaming(_ golden: Golden, context: GpuContext, system: ParticleSystem, volume: Volume, splatPass: SplatPass, marchPass: MarchPass) -> Row {
        let width = Int(golden.parameter("width")), height = Int(golden.parameter("height"))
        let splat = context.makeCommandBuffer(label: "validate splat")
        volume.encodeClear(splat)
        splatPass.encode(splat, system: system, volume: volume)
        splat.commit()
        splat.waitUntilCompleted()

        let camera = OrbitCamera()
        let targets = MarchPass.makeTargets(context: context, width: width, height: height, label: "beaming")
        let uniforms = MarchPass.uniforms(camera: camera, width: width, height: height, settings: .still,
                                          driftBudget: Constants.driftBudgetStill.value, redshift: true, starSeed: 0, stars: false)
        let render = context.makeCommandBuffer(label: "validate render")
        marchPass.encodeImage(render, uniforms: uniforms, volume: volume, blackbody: system.blackbody, targets: targets, counters: nil)
        render.commit()
        render.waitUntilCompleted()
        let gpuImage = readImage(targets.output, context: context)
        let gpuRatio = LensedRender.sideRatio(luminance: gpuImage.map(LensedRender.luminance), width: width, height: height)

        let emission = readVolume(volume.emission, context: context)
        let velocity = readVolume(volume.velocity, context: context).map { SIMD3($0.x, $0.y, $0.z) }
        let field = VolumeField(size: volume.size, halfExtent: Constants.volumeHalfExtent.value, emission: emission, velocity: velocity)
        let tanHalf = Double(tan(camera.fovY * 0.5))
        let oracleCamera = LensedRender.Camera(position: SIMD3<Double>(camera.position), right: SIMD3<Double>(camera.right), up: SIMD3<Double>(camera.up),
                                               forward: SIMD3<Double>(camera.forward), tanHalfFov: SIMD2(tanHalf * Double(width) / Double(height), tanHalf))
        let oracleImage = LensedRender.image(width: width, height: height, camera: oracleCamera, field: field, settings: .still)
        let oracleRatio = LensedRender.sideRatio(luminance: oracleImage.map(LensedRender.luminance), width: width, height: height)
        let measured = gpuRatio / oracleRatio
        return Row(golden: golden, measured: String(format: "gpu %.3f vs oracle %.3f, ratio %.3f", gpuRatio, oracleRatio, measured), passed: golden.passes(measured))
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
