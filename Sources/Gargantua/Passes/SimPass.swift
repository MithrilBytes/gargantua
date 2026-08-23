import Metal
import ShaderTypes

/// Pass 1. One compute dispatch over every particle.
@MainActor
final class SimPass {
    private let seed: MTLComputePipelineState
    private let step: MTLComputePipelineState

    init(context: GpuContext) {
        seed = context.computePipeline("sim.metal", "seedParticles")
        step = context.computePipeline("sim.metal", "stepParticles")
    }

    func encodeSeed(_ commandBuffer: MTLCommandBuffer, system: ParticleSystem) {
        dispatch(commandBuffer, pipeline: seed, system: system, label: "seed particles")
    }

    func encodeStep(_ commandBuffer: MTLCommandBuffer, system: ParticleSystem) {
        dispatch(commandBuffer, pipeline: step, system: system, label: "step particles")
        system.recordStep()
    }

    private func dispatch(_ commandBuffer: MTLCommandBuffer, pipeline: MTLComputePipelineState, system: ParticleSystem, label: String) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            Exit.operational("Metal could not create a compute encoder for \(label).")
        }
        encoder.label = label
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(system.buffer, offset: 0, index: 0)
        var uniforms = system.uniforms
        encoder.setBytes(&uniforms, length: MemoryLayout<SimUniforms>.stride, index: 1)
        encoder.setBuffer(system.inverseCdf, offset: 0, index: 2)
        let width = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
        encoder.dispatchThreads(MTLSize(width: system.count, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1))
        encoder.endEncoding()
    }
}
