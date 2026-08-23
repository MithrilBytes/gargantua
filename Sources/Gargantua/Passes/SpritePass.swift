import Metal
import Oracle
import ShaderTypes
import simd

/// Draws the particles as additive point sprites into a linear HDR target.
@MainActor
final class SpritePass {
    static let pixelFormat = MTLPixelFormat.rgba16Float
    private let pipeline: MTLRenderPipelineState
    private let context: GpuContext
    private(set) var target: MTLTexture?
    var exposure: Float = 1.0

    init(context: GpuContext) {
        self.context = context
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "sprites"
        descriptor.vertexFunction = context.function("sprites.metal", "spriteVertex", preciseMath: false)
        descriptor.fragmentFunction = context.function("sprites.metal", "spriteFragment", preciseMath: false)
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = SpritePass.pixelFormat
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .one
        attachment.destinationRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .one
        pipeline = context.renderPipeline(descriptor)
    }

    func resize(width: Int, height: Int) {
        if let target, target.width == width, target.height == height { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: SpritePass.pixelFormat, width: max(width, 1), height: max(height, 1), mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        target = context.makeTexture(descriptor, label: "hdr target")
    }

    func encode(_ commandBuffer: MTLCommandBuffer, system: ParticleSystem, camera: OrbitCamera) {
        guard let target else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            Exit.operational("Metal could not create the sprite render encoder.")
        }
        encoder.label = "sprites"
        let width = Float(target.width), height = Float(target.height)
        var uniforms = SpriteUniforms(
            viewProjection: camera.projectionMatrix(aspect: width / height) * camera.viewMatrix(),
            viewport: SIMD2(width, height),
            pixelsPerUnit: camera.pixelsPerUnit(viewportHeight: height),
            spriteRadius: Float(Constants.spriteRadius.value),
            exposure: exposure,
            peakTemperature: Float(Constants.peakTemperature.value),
            padding0: 0, padding1: 0)
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(system.buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<SpriteUniforms>.stride, index: 1)
        encoder.setVertexTexture(system.blackbody, index: 0)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: system.count)
        encoder.endEncoding()
    }
}
