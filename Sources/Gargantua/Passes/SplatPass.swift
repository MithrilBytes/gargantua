import Metal
import Oracle
import ShaderTypes

/// Pass 2. Bins particles into the volume with fixed point atomics, then
/// resolves the sums into textures and clears them.
@MainActor
final class SplatPass {
    private let splat: MTLComputePipelineState
    private let resolve: MTLComputePipelineState

    init(context: GpuContext) {
        splat = context.computePipeline("splat.metal", "splatParticles", preciseMath: false)
        resolve = context.computePipeline("splat.metal", "resolveVolume", preciseMath: false)
    }

    func encode(_ commandBuffer: MTLCommandBuffer, system: ParticleSystem, volume: Volume) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            Exit.operational("Metal could not create the splat encoder.")
        }
        encoder.label = "splat"
        var uniforms = SplatUniforms(
            volumeSize: UInt32(volume.size),
            particleCount: UInt32(system.count),
            halfExtent: Float(Constants.volumeHalfExtent.value),
            peakTemperature: Float(Constants.peakTemperature.value),
            emissionScale: Float(Constants.emissionScale.value),
            padding0: 0, padding1: 0, padding2: 0)
        encoder.setComputePipelineState(splat)
        encoder.setBuffer(system.buffer, offset: 0, index: 0)
        encoder.setBuffer(volume.emissionSums, offset: 0, index: 1)
        encoder.setBuffer(volume.momentumSums, offset: 0, index: 2)
        encoder.setBuffer(volume.massSums, offset: 0, index: 3)
        encoder.setBytes(&uniforms, length: MemoryLayout<SplatUniforms>.stride, index: 4)
        encoder.setTexture(system.blackbody, index: 0)
        encoder.dispatchThreads(MTLSize(width: system.count, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: min(splat.maxTotalThreadsPerThreadgroup, 256), height: 1, depth: 1))

        encoder.setComputePipelineState(resolve)
        encoder.setTexture(volume.emission, index: 0)
        encoder.setTexture(volume.velocity, index: 1)
        encoder.dispatchThreads(MTLSize(width: volume.size, height: volume.size, depth: volume.size),
                                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 4))
        encoder.endEncoding()
    }
}
