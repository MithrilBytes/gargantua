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

    /// Stills and other one shot paths deposit into all eight corners.
    var exactDeposit = false
    private var frame: UInt32 = 0

    private func uniforms(system: ParticleSystem, volume: Volume) -> SplatUniforms {
        SplatUniforms(
            volumeSize: UInt32(volume.size),
            particleCount: UInt32(system.count),
            halfExtent: Float(Constants.volumeHalfExtent.value),
            peakTemperature: Float(Constants.peakTemperature.value),
            emissionScale: Float(Constants.emissionScale.value),
            frame: frame,
            exactDeposit: exactDeposit ? 1 : 0,
            seed: SIMD2(UInt32(truncatingIfNeeded: system.seed), UInt32(truncatingIfNeeded: system.seed >> 32)))
    }

    /// The binning dispatch alone; the bench times the phases separately.
    func encodeBin(_ commandBuffer: MTLCommandBuffer, system: ParticleSystem, volume: Volume) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            Exit.operational("Metal could not create the splat encoder.")
        }
        encoder.label = "splat bin"
        var u = uniforms(system: system, volume: volume)
        encoder.setComputePipelineState(splat)
        encoder.setBuffer(system.buffer, offset: 0, index: 0)
        encoder.setBuffer(volume.emissionSums, offset: 0, index: 1)
        encoder.setBuffer(volume.momentumSums, offset: 0, index: 2)
        encoder.setBuffer(volume.massSums, offset: 0, index: 3)
        encoder.setBytes(&u, length: MemoryLayout<SplatUniforms>.stride, index: 4)
        encoder.dispatchThreads(MTLSize(width: system.count, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: min(splat.maxTotalThreadsPerThreadgroup, 256), height: 1, depth: 1))
        encoder.endEncoding()
    }

    /// The resolve dispatch alone.
    func encodeResolve(_ commandBuffer: MTLCommandBuffer, system: ParticleSystem, volume: Volume) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            Exit.operational("Metal could not create the resolve encoder.")
        }
        encoder.label = "splat resolve"
        var u = uniforms(system: system, volume: volume)
        encoder.setComputePipelineState(resolve)
        encoder.setBuffer(volume.emissionSums, offset: 0, index: 1)
        encoder.setBuffer(volume.momentumSums, offset: 0, index: 2)
        encoder.setBuffer(volume.massSums, offset: 0, index: 3)
        encoder.setBytes(&u, length: MemoryLayout<SplatUniforms>.stride, index: 4)
        encoder.setTexture(volume.emission, index: 0)
        encoder.setTexture(volume.velocity, index: 1)
        encoder.setTexture(system.blackbody, index: 2)
        encoder.dispatchThreads(MTLSize(width: volume.size, height: volume.size, depth: volume.size),
                                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 4))
        encoder.endEncoding()
    }

    func encode(_ commandBuffer: MTLCommandBuffer, system: ParticleSystem, volume: Volume) {
        encodeBin(commandBuffer, system: system, volume: volume)
        encodeResolve(commandBuffer, system: system, volume: volume)
        volume.encodeClear(commandBuffer)
        frame &+= 1
    }
}
