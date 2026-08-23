import Metal
import MetalFX

/// MetalFX temporal upscaling from the march resolution to the drawable.
/// The march jitters its sample positions and writes depth and motion for
/// it. Nil when the device or OS cannot provide the scaler.
@MainActor
final class Upscaler {
    let inputWidth: Int
    let inputHeight: Int
    let outputWidth: Int
    let outputHeight: Int
    let output: MTLTexture
    private let scaler: MTLFXTemporalScaler
    private var pendingReset = true

    init?(context: GpuContext, inputWidth: Int, inputHeight: Int, outputWidth: Int, outputHeight: Int) {
        guard MTLFXTemporalScalerDescriptor.supportsDevice(context.device) else { return nil }
        let descriptor = MTLFXTemporalScalerDescriptor()
        descriptor.inputWidth = inputWidth
        descriptor.inputHeight = inputHeight
        descriptor.outputWidth = outputWidth
        descriptor.outputHeight = outputHeight
        descriptor.colorTextureFormat = MarchPass.pixelFormat
        descriptor.depthTextureFormat = .r32Float
        descriptor.motionTextureFormat = .rg16Float
        descriptor.outputTextureFormat = MarchPass.pixelFormat
        descriptor.isAutoExposureEnabled = false
        descriptor.isInputContentPropertiesEnabled = false
        guard let scaler = descriptor.makeTemporalScaler(device: context.device) else { return nil }
        self.scaler = scaler
        self.inputWidth = inputWidth
        self.inputHeight = inputHeight
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: MarchPass.pixelFormat, width: outputWidth, height: outputHeight, mipmapped: false)
        outputDescriptor.usage = scaler.outputTextureUsage.union([.shaderRead])
        outputDescriptor.storageMode = .private
        output = context.makeTexture(outputDescriptor, label: "upscaled")
        scaler.motionVectorScaleX = 1
        scaler.motionVectorScaleY = 1
        scaler.isDepthReversed = false
    }

    /// Forget history at the next frame (camera cut, preset switch, reseed).
    func reset() {
        pendingReset = true
    }

    func encode(_ commandBuffer: MTLCommandBuffer, color: MTLTexture, depth: MTLTexture, motion: MTLTexture, jitter: SIMD2<Float>) {
        scaler.colorTexture = color
        scaler.depthTexture = depth
        scaler.motionTexture = motion
        scaler.outputTexture = output
        scaler.jitterOffsetX = jitter.x
        scaler.jitterOffsetY = jitter.y
        scaler.reset = pendingReset
        pendingReset = false
        scaler.encode(commandBuffer: commandBuffer)
    }
}

/// Halton sequence offsets in [-0.5, 0.5), bases 2 and 3, eight frames long.
/// Halton, J. H., 1960. On the efficiency of certain quasi random sequences
/// of points in evaluating multi dimensional integrals. Numerische
/// Mathematik 2, 84.
enum Jitter {
    static let length = 8

    static func halton(_ index: Int, base: Int) -> Float {
        var result: Float = 0
        var fraction: Float = 1 / Float(base)
        var i = index
        while i > 0 {
            result += fraction * Float(i % base)
            i /= base
            fraction /= Float(base)
        }
        return result
    }

    static func offset(frame: Int) -> SIMD2<Float> {
        let index = frame % length + 1
        return SIMD2(halton(index, base: 2) - 0.5, halton(index, base: 3) - 0.5)
    }
}
