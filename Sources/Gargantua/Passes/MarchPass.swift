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
    private(set) var output: MTLTexture?
    private(set) var debug: MTLTexture?
    private var counters: [MTLBuffer] = []
    private var counterSlot = 0

    init(context: GpuContext) {
        self.context = context
        image = context.computePipeline("march.metal", "marchImage", preciseMath: true)
        probe = context.computePipeline("march.metal", "probeRays", preciseMath: true)
        for slot in 0..<3 {
            let buffer = context.makeBuffer(bytes: MemoryLayout<MarchCounters>.stride, label: "march counters \(slot)", shared: true)
            memset(buffer.contents(), 0, buffer.length)
            counters.append(buffer)
        }
    }

    static func makeTargets(context: GpuContext, width: Int, height: Int, label: String) -> (output: MTLTexture, debug: MTLTexture) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: max(width, 1), height: max(height, 1), mipmapped: false)
        descriptor.usage = [.shaderWrite, .shaderRead]
        descriptor.storageMode = .private
        return (context.makeTexture(descriptor, label: "\(label) output"), context.makeTexture(descriptor, label: "\(label) debug"))
    }

    func resize(width: Int, height: Int) {
        if let output, output.width == width, output.height == height { return }
        let targets = MarchPass.makeTargets(context: context, width: width, height: height, label: "march")
        output = targets.output
        debug = targets.debug
    }

    static func settings(_ s: Schwarzschild.Settings) -> GeodesicSettings {
        GeodesicSettings(stepFactor: Float(s.stepFactor), stepMin: Float(s.stepMin), stepMax: Float(min(s.stepMax, 1e9)),
                         captureRadius: Float(s.captureRadius), escapeRadius: Float(s.escapeRadius),
                         stepCap: UInt32(s.stepCap), padding0: 0, padding1: 0)
    }

    static func uniforms(camera: OrbitCamera, width: Int, height: Int, tileOrigin: (Int, Int) = (0, 0),
                         settings: Schwarzschild.Settings, driftBudget: Double, redshift: Bool, starSeed: UInt32) -> MarchUniforms {
        let tanHalf = tan(camera.fovY * 0.5)
        return MarchUniforms(
            cameraPosition: camera.position,
            cameraRight: camera.right,
            cameraUp: camera.up,
            cameraForward: camera.forward,
            tanHalfFov: SIMD2(tanHalf * Float(width) / Float(height), tanHalf),
            resolution: SIMD2(UInt32(width), UInt32(height)),
            tileOrigin: SIMD2(UInt32(tileOrigin.0), UInt32(tileOrigin.1)),
            volumeHalfExtent: Float(Constants.volumeHalfExtent.value),
            opacityScale: Float(Constants.volumeOpacity.value),
            starBrightness: Float(Constants.starBrightness.value),
            driftBudget: Float(driftBudget),
            starSeed: starSeed,
            redshift: redshift ? 1 : 0,
            padding0: 0, padding1: 0,
            geodesic: MarchPass.settings(settings))
    }

    /// Render a tile (or the whole image when the targets cover it).
    func encodeImage(_ commandBuffer: MTLCommandBuffer, uniforms: MarchUniforms, volume: Volume, blackbody: MTLTexture,
                     output: MTLTexture, debug: MTLTexture, counters: MTLBuffer?) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            Exit.operational("Metal could not create the march encoder.")
        }
        encoder.label = "march"
        var u = uniforms
        encoder.setComputePipelineState(image)
        encoder.setTexture(output, index: 0)
        encoder.setTexture(debug, index: 1)
        encoder.setTexture(volume.emission, index: 2)
        encoder.setTexture(volume.velocity, index: 3)
        encoder.setTexture(blackbody, index: 4)
        encoder.setBytes(&u, length: MemoryLayout<MarchUniforms>.stride, index: 0)
        encoder.setBuffer(counters ?? self.counters[0], offset: 0, index: 1)
        encoder.dispatchThreads(MTLSize(width: output.width, height: output.height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 32, height: 4, depth: 1))
        encoder.endEncoding()
    }

    /// Interactive frame: rotates through the counter ring so the CPU reads
    /// a buffer the GPU finished frames ago.
    func encodeFrame(_ commandBuffer: MTLCommandBuffer, uniforms: MarchUniforms, volume: Volume, blackbody: MTLTexture) {
        guard let output, let debug else { return }
        let slot = counters[counterSlot]
        encodeImage(commandBuffer, uniforms: uniforms, volume: volume, blackbody: blackbody, output: output, debug: debug, counters: slot)
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
        encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: min(probe.maxTotalThreadsPerThreadgroup, 64), height: 1, depth: 1))
        encoder.endEncoding()
    }
}
