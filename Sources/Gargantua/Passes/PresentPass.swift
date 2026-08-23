import Metal
import ShaderTypes
import simd

/// Pass 4. Tone maps the HDR image into a drawable sized target and composites
/// the hud texture. It draws; it never measures.
@MainActor
final class PresentPass {
    private let tonemap: MTLRenderPipelineState
    private let hud: MTLRenderPipelineState
    var exposure: Float = 1.0

    init(context: GpuContext, pixelFormat: MTLPixelFormat) {
        let base = MTLRenderPipelineDescriptor()
        base.label = "tonemap"
        base.vertexFunction = context.function("present.metal", "fullscreenVertex", preciseMath: false)
        base.fragmentFunction = context.function("present.metal", "tonemapFragment", preciseMath: false)
        base.colorAttachments[0].pixelFormat = pixelFormat
        tonemap = context.renderPipeline(base)

        let overlay = MTLRenderPipelineDescriptor()
        overlay.label = "hud"
        overlay.vertexFunction = context.function("present.metal", "hudVertex", preciseMath: false)
        overlay.fragmentFunction = context.function("present.metal", "hudFragment", preciseMath: false)
        let attachment = overlay.colorAttachments[0]!
        attachment.pixelFormat = pixelFormat
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        hud = context.renderPipeline(overlay)
    }

    /// Encode into any render pass whose color attachment matches the pixel
    /// format given at init. The hud is drawn at its native pixel size with a
    /// margin, anchored at the top left.
    func encode(_ commandBuffer: MTLCommandBuffer, pass: MTLRenderPassDescriptor, hdr: MTLTexture, hudTexture: MTLTexture?, targetWidth: Int, targetHeight: Int) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            Exit.operational("Metal could not create the present render encoder.")
        }
        encoder.label = "present"
        var uniforms = PresentUniforms(hudRect: SIMD4(0, 0, 0, 0), exposure: exposure, hudVisible: 0, padding0: 0, padding1: 0)
        if let hudTexture {
            let margin: Float = 16
            let w = Float(targetWidth), h = Float(targetHeight)
            let x0 = -1 + 2 * margin / w
            let x1 = x0 + 2 * Float(hudTexture.width) / w
            let y1 = 1 - 2 * margin / h
            let y0 = y1 - 2 * Float(hudTexture.height) / h
            uniforms.hudRect = SIMD4(x0, y0, x1, y1)
            uniforms.hudVisible = 1
        }
        encoder.setRenderPipelineState(tonemap)
        encoder.setFragmentTexture(hdr, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<PresentUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        if let hudTexture {
            encoder.setRenderPipelineState(hud)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PresentUniforms>.stride, index: 0)
            encoder.setFragmentTexture(hudTexture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        encoder.endEncoding()
    }
}
