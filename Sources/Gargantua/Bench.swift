import Foundation
import Metal
import Oracle

/// `gargantua bench`: times every pass for both strategies on the same
/// scene, prints a verdict and writes a dated JSON report. Each timing is
/// one command buffer waited to completion, so nothing overlaps.
@MainActor
enum Bench {
    struct Timing {
        let mean: Double
        let median: Double
        let maximum: Double

        init(_ samples: [Double]) {
            let sorted = samples.sorted()
            mean = samples.isEmpty ? 0 : samples.reduce(0, +) / Double(samples.count)
            median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
            maximum = sorted.last ?? 0
        }

        var json: [String: Double] {
            ["mean_ms": mean * 1000, "p50_ms": median * 1000, "max_ms": maximum * 1000]
        }
    }

    static let outputWidth = 1920
    static let outputHeight = 1080
    static let warmup = 5
    static let iterations = 30

    static func run(_ options: Options) -> Never {
        let context = GpuContext()
        var configuration = Configuration.make(options)
        configuration.strategy = .bake
        let extra = UInt64(outputWidth * outputHeight) * 12
        if let refusal = context.budget.refusal(bytes: configuration.bytes + extra, describing: "The bench at preset \(configuration.preset.rawValue)") {
            Exit.operational(refusal)
        }
        if configuration.preset.gated {
            Console.line(configuration.preset.thermalNote)
        }

        let simPass = SimPass(context: context)
        let splatPass = SplatPass(context: context)
        let marchPass = MarchPass(context: context)
        let bakePass = BakePass(context: context)
        let presentPass = PresentPass(context: context, pixelFormat: .bgra8Unorm_srgb)
        let system = ParticleSystem(context: context, count: configuration.particles, seed: configuration.seed, potential: .paczynskiWiita)
        let volume = Volume(context: context, size: configuration.volume)
        let width = configuration.marchWidth, height = configuration.marchHeight
        marchPass.resize(width: width, height: height)
        bakePass.resize(width: width, height: height)
        let upscaler = Upscaler(context: context, inputWidth: width, inputHeight: height, outputWidth: outputWidth, outputHeight: outputHeight)
        let presentDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: outputWidth, height: outputHeight, mipmapped: false)
        presentDescriptor.usage = [.renderTarget]
        presentDescriptor.storageMode = .private
        let presented = context.makeTexture(presentDescriptor, label: "bench present")
        let camera = OrbitCamera()

        Console.line("settling \(configuration.particles) particles")
        Validate.advance(system, steps: Int(Constants.stillSettleSteps.value) / Int(Constants.simulationSubsteps.value), context: context, simPass: simPass, seedFirst: true)
        let clear = context.makeCommandBuffer(label: "bench clear")
        volume.encodeClear(clear)
        clear.commit()
        clear.waitUntilCompleted()

        guard let targets = marchPass.targets else { Exit.operational("The march targets were not allocated.") }
        let uniforms = MarchPass.uniforms(camera: camera, width: width, height: height, settings: .interactive,
                                          driftBudget: Constants.driftBudgetInteractive.value, redshift: true,
                                          starSeed: UInt32(truncatingIfNeeded: configuration.seed),
                                          bakeSpacing: bakePass.spacing(volumeSize: volume.size), tables: marchPass.tables)
        var bakeUniforms = uniforms
        bakeUniforms.geodesic = MarchPass.settings(.still)

        func time(_ label: String, _ encode: (MTLCommandBuffer) -> Void) -> Timing {
            var samples: [Double] = []
            for i in 0..<(warmup + iterations) {
                let commandBuffer = context.makeCommandBuffer(label: "bench \(label)")
                encode(commandBuffer)
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
                if i >= warmup { samples.append(commandBuffer.gpuEndTime - commandBuffer.gpuStartTime) }
            }
            let timing = Timing(samples)
            Console.line(String(format: "%-8@ mean %7.3f ms  p50 %7.3f ms  max %7.3f ms", label, timing.mean * 1000, timing.median * 1000, timing.maximum * 1000))
            return timing
        }

        Console.line("timing \(iterations) iterations per pass after \(warmup) warmups, \(width) by \(height) march, \(outputWidth) by \(outputHeight) output")
        var passes: [String: Timing] = [:]
        passes["sim"] = time("sim") { simPass.encodeStep($0, system: system) }
        passes["splat"] = time("splat") { splatPass.encode($0, system: system, volume: volume) }
        passes["march"] = time("march") { marchPass.encodeImage($0, uniforms: uniforms, volume: volume, blackbody: system.blackbody, targets: targets, counters: nil) }
        var bakeChunks: [Double] = []
        for i in 0..<(warmup + iterations) {
            bakePass.invalidate()
            var total = 0.0
            while !bakePass.complete {
                let commandBuffer = context.makeCommandBuffer(label: "bench bake chunk")
                bakePass.encodeBakeChunk(commandBuffer, camera: camera, uniforms: bakeUniforms, tables: marchPass.tables)
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
                total += commandBuffer.gpuEndTime - commandBuffer.gpuStartTime
            }
            if i >= warmup { bakeChunks.append(total) }
        }
        passes["bake"] = Timing(bakeChunks)
        Console.line(String(format: "%-8@ mean %7.3f ms  p50 %7.3f ms  max %7.3f ms  (sum of %d chunks)", "bake", passes["bake"]!.mean * 1000, passes["bake"]!.median * 1000, passes["bake"]!.maximum * 1000, Int(Constants.bakeFrames.value)))
        passes["walk"] = time("walk") { bakePass.encodeWalk($0, uniforms: uniforms, volume: volume, blackbody: system.blackbody, targets: targets) }
        if let upscaler {
            passes["upscale"] = time("upscale") { upscaler.encode($0, color: targets.output, depth: targets.depth, motion: targets.motion, jitter: SIMD2(0, 0)) }
        }
        passes["present"] = time("present") { commandBuffer in
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = presented
            pass.colorAttachments[0].loadAction = .dontCare
            pass.colorAttachments[0].storeAction = .store
            presentPass.encode(commandBuffer, pass: pass, hdr: upscaler?.output ?? targets.output, debug: nil, hudTexture: nil, targetWidth: outputWidth, targetHeight: outputHeight)
        }

        func mean(_ name: String) -> Double {
            guard let timing = passes[name] else { return 0 }
            return timing.mean
        }
        let shared = mean("sim") + mean("splat") + mean("upscale") + mean("present")
        let marchFrame = shared + mean("march")
        let bakeFrame = shared + mean("walk")
        let bakeCost = mean("bake")
        let pixels = UInt64(width * height)
        let sampleBytes = pixels * UInt64(Constants.bakeSamples.value) * 8
        let bakeBytes = sampleBytes + pixels * 16
        let verdict = String(format: "march frame %.1f ms, bake frame %.1f ms after a %.1f ms bake per camera stop and %@ of samples (%u rays over the sample budget); %@",
                             marchFrame * 1000, bakeFrame * 1000, bakeCost * 1000, formatBytes(bakeBytes), bakePass.overflowCount,
                             bakeFrame < marchFrame ? "the walk is faster while the camera holds still, the march is free to move" : "the march is faster")
        Console.line(verdict)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let stamp = formatter.string(from: Date())
        var report: [String: Any] = [:]
        report["version"] = Program.version
        report["date"] = stamp
        report["device"] = context.device.name
        report["os"] = ProcessInfo.processInfo.operatingSystemVersionString
        report["preset"] = configuration.preset.rawValue
        report["particles"] = configuration.particles
        report["volume"] = configuration.volume
        report["march"] = [width, height]
        report["output"] = [outputWidth, outputHeight]
        report["iterations"] = iterations
        report["passes"] = passes.mapValues { $0.json }
        report["frames"] = ["march_ms": marchFrame * 1000, "bake_ms": bakeFrame * 1000]
        report["bake"] = ["bytes": bakeBytes, "overflow_rays": bakePass.overflowCount]
        report["verdict"] = verdict
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: "bench/results")
        let url = directory.appending(path: "\(stamp).json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url)
        } catch {
            Exit.operational("Could not write the bench report to \(url.path): \(error.localizedDescription)")
        }
        Console.line("report \(url.path)")
        exit(0)
    }
}
