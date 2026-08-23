import Metal

/// The cube the splat pass bins particles into: fixed point sums for the
/// atomics and the resolved half precision textures the march pass samples.
@MainActor
final class Volume {
    let size: Int
    let emissionSums: MTLBuffer
    let momentumSums: MTLBuffer
    let massSums: MTLBuffer
    let emission: MTLTexture
    let velocity: MTLTexture

    init(context: GpuContext, size: Int) {
        self.size = size
        let voxels = size * size * size
        emissionSums = context.makeBuffer(bytes: voxels * 2 * 4, label: "emission sums")
        momentumSums = context.makeBuffer(bytes: voxels * 3 * 4, label: "momentum sums")
        massSums = context.makeBuffer(bytes: voxels * 4, label: "mass sums")
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba16Float
        descriptor.width = size
        descriptor.height = size
        descriptor.depth = size
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        emission = context.makeTexture(descriptor, label: "emission volume")
        velocity = context.makeTexture(descriptor, label: "velocity volume")
    }

    /// Zero the sums. Private buffers start undefined, so this runs once
    /// before the first splat.
    func encodeClear(_ commandBuffer: MTLCommandBuffer) {
        guard let blit = commandBuffer.makeBlitCommandEncoder() else {
            Exit.operational("Metal could not create the volume clear encoder.")
        }
        blit.label = "clear volume"
        for buffer in [emissionSums, momentumSums, massSums] {
            blit.fill(buffer: buffer, range: 0..<buffer.length, value: 0)
        }
        blit.endEncoding()
    }
}
