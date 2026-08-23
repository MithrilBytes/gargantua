import Metal
import Oracle
import ShaderTypes

/// The bake strategy's resources and kernels: bake rays once for a
/// stationary camera, then walk the stored samples every frame.
@MainActor
final class BakePass {
    private let bake: MTLComputePipelineState
    private let walk: MTLComputePipelineState
    private let context: GpuContext
    private(set) var samples: MTLBuffer?
    private(set) var headers: MTLBuffer?
    private let overflow: MTLBuffer
    private(set) var width = 0
    private(set) var height = 0
    /// Rows baked so far for the current camera.
    private(set) var bakedRows = 0
    private(set) var bakedCamera: OrbitCamera?

    init(context: GpuContext) {
        self.context = context
        bake = context.computePipeline("bake.metal", "bakeRays", preciseMath: true)
        walk = context.computePipeline("bake.metal", "walkRays", preciseMath: false)
        overflow = context.makeBuffer(bytes: 4, label: "bake overflow", shared: true)
        memset(overflow.contents(), 0, 4)
    }

    var capacity: Int { Int(Constants.bakeSamples.value) }

    func resize(width: Int, height: Int) {
        if self.width == width, self.height == height, samples != nil { return }
        self.width = width
        self.height = height
        samples = context.makeBuffer(bytes: width * height * capacity * 8, label: "bake samples")
        headers = context.makeBuffer(bytes: width * height * 16, label: "bake headers")
        invalidate()
    }

    func invalidate() {
        bakedRows = 0
        bakedCamera = nil
    }

    var complete: Bool { bakedRows >= height && bakedCamera != nil }

    /// Rays the last complete bake could not fit in the sample budget.
    var overflowCount: UInt32 { overflow.contents().load(as: UInt32.self) }

    func spacing(volumeSize: Int) -> Float {
        Float(2.0 * Constants.volumeHalfExtent.value / Double(volumeSize) * Constants.bakeSpacingVoxels.value)
    }

    /// Bake the next chunk of rows for `camera`, spread over BAKE_FRAMES frames.
    func encodeBakeChunk(_ commandBuffer: MTLCommandBuffer, camera: OrbitCamera, uniforms base: MarchUniforms) {
        guard let samples, let headers else { return }
        if bakedCamera == nil {
            bakedCamera = camera
            bakedRows = 0
            memset(overflow.contents(), 0, 4)
        }
        let rows = min(max(height / Int(Constants.bakeFrames.value), 1), height - bakedRows)
        guard rows > 0, let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "bake rows \(bakedRows) to \(bakedRows + rows)"
        var uniforms = base
        uniforms.tileOrigin = SIMD2(0, UInt32(bakedRows))
        encoder.setComputePipelineState(bake)
        encoder.setBuffer(samples, offset: 0, index: 0)
        encoder.setBuffer(headers, offset: 0, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<MarchUniforms>.stride, index: 2)
        encoder.setBuffer(overflow, offset: 0, index: 3)
        encoder.dispatchThreads(MTLSize(width: width, height: rows, depth: 1), threadsPerThreadgroup: MTLSize(width: 32, height: 4, depth: 1))
        encoder.endEncoding()
        bakedRows += rows
    }

    /// Bake everything in one command buffer; for the bench only.
    func encodeFullBake(_ commandBuffer: MTLCommandBuffer, camera: OrbitCamera, uniforms: MarchUniforms) {
        invalidate()
        while !complete {
            encodeBakeChunk(commandBuffer, camera: camera, uniforms: uniforms)
        }
    }

    func encodeWalk(_ commandBuffer: MTLCommandBuffer, uniforms: MarchUniforms, volume: Volume, blackbody: MTLTexture, targets: MarchPass.Targets) {
        guard let samples, let headers, let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "walk"
        var u = uniforms
        encoder.setComputePipelineState(walk)
        encoder.setTexture(targets.output, index: 0)
        encoder.setTexture(volume.emission, index: 2)
        encoder.setTexture(volume.velocity, index: 3)
        encoder.setTexture(blackbody, index: 4)
        encoder.setTexture(targets.depth, index: 5)
        encoder.setTexture(targets.motion, index: 6)
        encoder.setBuffer(samples, offset: 0, index: 0)
        encoder.setBuffer(headers, offset: 0, index: 1)
        encoder.setBytes(&u, length: MemoryLayout<MarchUniforms>.stride, index: 2)
        encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1), threadsPerThreadgroup: MTLSize(width: 32, height: 4, depth: 1))
        encoder.endEncoding()
    }
}

