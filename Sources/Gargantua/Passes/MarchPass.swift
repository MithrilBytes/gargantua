import Metal
import Oracle
import ShaderTypes
import simd

/// Pass 3. One thread per ray through the lensed volume, plus the probe
/// entry point validation uses to integrate arbitrary rays with the same
/// code.
@MainActor
final class MarchPass {
    static let pixelFormat = MTLPixelFormat.rgba16Float
    private let image: MTLComputePipelineState
    private let probe: MTLComputePipelineState
    private let context: GpuContext
    let tables: DeflectionTables
    private(set) var output: MTLTexture?
    private(set) var debug: MTLTexture?
    private(set) var depth: MTLTexture?
    private(set) var motion: MTLTexture?
    private var counters: [MTLBuffer] = []
    private var counterSlot = 0

    init(context: GpuContext) {
        self.context = context
        image = context.computePipeline("march.metal", "marchImage", preciseMath: true)
        probe = context.computePipeline("march.metal", "probeRays", preciseMath: true)
        tables = DeflectionTables(context: context)
        for slot in 0..<3 {
            let buffer = context.makeBuffer(bytes: MemoryLayout<MarchCounters>.stride, label: "march counters \(slot)", shared: true)
            memset(buffer.contents(), 0, buffer.length)
            counters.append(buffer)
        }
    }

    struct Targets {
        let output: MTLTexture
        let debug: MTLTexture
        let depth: MTLTexture
        let motion: MTLTexture
    }

    static func makeTargets(context: GpuContext, width: Int, height: Int, label: String) -> Targets {
        func make(_ format: MTLPixelFormat, _ name: String) -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: max(width, 1), height: max(height, 1), mipmapped: false)
            descriptor.usage = [.shaderWrite, .shaderRead, .renderTarget]
            descriptor.storageMode = .private
            return context.makeTexture(descriptor, label: "\(label) \(name)")
        }
        return Targets(output: make(pixelFormat, "output"), debug: make(pixelFormat, "debug"), depth: make(.r32Float, "depth"), motion: make(.rg16Float, "motion"))
    }

    func resize(width: Int, height: Int) {
        if let output, output.width == width, output.height == height { return }
        let targets = MarchPass.makeTargets(context: context, width: width, height: height, label: "march")
        output = targets.output
        debug = targets.debug
        depth = targets.depth
        motion = targets.motion
    }

    static func settings(_ s: Schwarzschild.Settings) -> GeodesicSettings {
        GeodesicSettings(stepFactor: Float(s.stepFactor), stepMin: Float(s.stepMin), stepMax: Float(min(s.stepMax, 1e9)),
                         captureRadius: Float(s.captureRadius), escapeRadius: Float(s.escapeRadius),
                         stepCap: UInt32(s.stepCap), emptyStepFactor: Float(s.emptyStepFactor), emptyStepMax: Float(min(s.emptyStepMax, 1e9)))
    }

    static func uniforms(camera: OrbitCamera, previous: OrbitCamera? = nil, jitter: SIMD2<Float> = SIMD2(0, 0),
                         width: Int, height: Int, tileOrigin: (Int, Int) = (0, 0),
                         settings: Schwarzschild.Settings, driftBudget: Double, redshift: Bool, starSeed: UInt32, stars: Bool = true,
                         bakeSpacing: Float = 0, tables: DeflectionTables? = nil) -> MarchUniforms {
        let tanHalf = tan(camera.fovY * 0.5)
        let before = previous ?? camera
        var uniforms = MarchUniforms(
            cameraPosition: camera.position,
            cameraRight: camera.right,
            cameraUp: camera.up,
            cameraForward: camera.forward,
            tanHalfFov: SIMD2(tanHalf * Float(width) / Float(height), tanHalf),
            resolution: SIMD2(UInt32(width), UInt32(height)),
            tileOrigin: SIMD2(UInt32(tileOrigin.0), UInt32(tileOrigin.1)),
            volumeHalfExtent: Float(Constants.volumeHalfExtent.value),
            opacityScale: Float(Constants.volumeOpacity.value),
            starBrightness: stars ? Float(Constants.starBrightness.value) : 0,
            driftBudget: Float(driftBudget),
            starSeed: starSeed,
            redshift: redshift ? 1 : 0,
            bakeSpacing: bakeSpacing,
            bakeCapacity: Constants.bakeSamples.value,
            sphereRadius: 0, cameraRadius: 0, sphereMaxB: 0, sphereTableMaxB: 0, cameraMaxB: 0, skyMinB: 0, skyMaxB: 0, padding2: 0,
            jitter: jitter,
            previousPosition: before.position,
            previousRight: before.right,
            previousUp: before.up,
            previousForward: before.forward,
            geodesic: MarchPass.settings(settings))
        if let tables {
            tables.update(cameraRadius: Double(camera.distance))
            tables.apply(to: &uniforms)
        }
        return uniforms
    }

    /// Render a tile (or the whole image when the targets cover it).
    static let defaultThreadgroup = MTLSize(width: Int(Constants.marchThreadgroupWidth.value), height: Int(Constants.marchThreadgroupHeight.value), depth: 1)

    func encodeImage(_ commandBuffer: MTLCommandBuffer, uniforms: MarchUniforms, volume: Volume, blackbody: MTLTexture,
                     targets: Targets, counters: MTLBuffer?, threadgroup: MTLSize = MarchPass.defaultThreadgroup) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            Exit.operational("Metal could not create the march encoder.")
        }
        encoder.label = "march"
        var u = uniforms
        encoder.setComputePipelineState(image)
        encoder.setTexture(targets.output, index: 0)
        encoder.setTexture(targets.debug, index: 1)
        encoder.setTexture(volume.emission, index: 2)
        encoder.setTexture(volume.velocity, index: 3)
        encoder.setTexture(blackbody, index: 4)
        encoder.setTexture(targets.depth, index: 5)
        encoder.setTexture(targets.motion, index: 6)
        tables.bind(encoder)
        encoder.setBytes(&u, length: MemoryLayout<MarchUniforms>.stride, index: 0)
        encoder.setBuffer(counters ?? self.counters[0], offset: 0, index: 1)
        encoder.dispatchThreads(MTLSize(width: targets.output.width, height: targets.output.height, depth: 1),
                                threadsPerThreadgroup: threadgroup)
        encoder.endEncoding()
    }

    /// Interactive frame: rotates through the counter ring so the CPU reads
    /// a buffer the GPU finished frames ago.
    var targets: Targets? {
        guard let output, let debug, let depth, let motion else { return nil }
        return Targets(output: output, debug: debug, depth: depth, motion: motion)
    }

    func encodeFrame(_ commandBuffer: MTLCommandBuffer, uniforms: MarchUniforms, volume: Volume, blackbody: MTLTexture) {
        guard let targets else { return }
        let slot = counters[counterSlot]
        encodeImage(commandBuffer, uniforms: uniforms, volume: volume, blackbody: blackbody, targets: targets, counters: slot)
        counterSlot = (counterSlot + 1) % counters.count
    }

    /// Counters from the oldest ring slot, zeroed after reading.
    func readCounters() -> MarchCounters {
        let slot = counters[counterSlot]
        let value = slot.contents().load(as: MarchCounters.self)
        memset(slot.contents(), 0, slot.length)
        return value
    }

    func encodeProbes(_ commandBuffer: MTLCommandBuffer, probes: MTLBuffer, results: MTLBuffer, count: Int,
                      uniforms: MarchUniforms, volume: Volume, blackbody: MTLTexture) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            Exit.operational("Metal could not create the probe encoder.")
        }
        encoder.label = "probe rays"
        var u = uniforms
        var n = UInt32(count)
        encoder.setComputePipelineState(probe)
        encoder.setBuffer(probes, offset: 0, index: 0)
        encoder.setBuffer(results, offset: 0, index: 1)
        encoder.setBytes(&u, length: MemoryLayout<MarchUniforms>.stride, index: 2)
        encoder.setBytes(&n, length: MemoryLayout<UInt32>.stride, index: 3)
        encoder.setTexture(volume.emission, index: 2)
        encoder.setTexture(volume.velocity, index: 3)
        encoder.setTexture(blackbody, index: 4)
        tables.bind(encoder)
        encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: min(probe.maxTotalThreadsPerThreadgroup, 64), height: 1, depth: 1))
        encoder.endEncoding()
    }
}
