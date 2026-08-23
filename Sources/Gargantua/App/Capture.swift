import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

/// Tone maps a linear image into 8 bit sRGB, reads it back and writes a
/// PNG. The only disk writes in the program, and only when asked for.
@MainActor
final class Capture {
    struct Pixels: @unchecked Sendable {
        let buffer: MTLBuffer
        let width: Int
        let height: Int
    }

    private let context: GpuContext
    private let presentPass: PresentPass
    private let pixelFormat: MTLPixelFormat

    init(context: GpuContext, presentPass: PresentPass, pixelFormat: MTLPixelFormat) {
        self.context = context
        self.presentPass = presentPass
        self.pixelFormat = pixelFormat
    }

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Pictures/gargantua")
    }

    static func nextScreenshotPath() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return directory.appending(path: "gargantua-\(formatter.string(from: Date())).png")
    }

    /// Encode a hud free present of `hdr` into an offscreen target and copy
    /// it to host memory. Returns the readback buffer the GPU fills.
    func encodeReadback(_ commandBuffer: MTLCommandBuffer, hdr: MTLTexture) -> Pixels {
        let width = hdr.width, height = hdr.height
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let target = context.makeTexture(descriptor, label: "capture")
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        presentPass.encode(commandBuffer, pass: pass, hdr: hdr, debug: nil, hudTexture: nil, targetWidth: width, targetHeight: height)

        let buffer = context.makeBuffer(bytes: width * height * 4, label: "capture readback", shared: true)
        guard let blit = commandBuffer.makeBlitCommandEncoder() else {
            Exit.operational("Metal could not create the capture blit encoder.")
        }
        blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: buffer, destinationOffset: 0, destinationBytesPerRow: width * 4, destinationBytesPerImage: width * height * 4)
        blit.endEncoding()
        return Pixels(buffer: buffer, width: width, height: height)
    }

    /// Interactive screenshot: the completion runs off the main thread once
    /// the GPU is done, with the written path or nil.
    func encodeScreenshot(_ commandBuffer: MTLCommandBuffer, hdr: MTLTexture, completion: @escaping @Sendable (URL?) -> Void) {
        let pixels = encodeReadback(commandBuffer, hdr: hdr)
        let path = Capture.nextScreenshotPath()
        commandBuffer.addCompletedHandler { _ in
            completion(Capture.writePNG(pixels, to: path) ? path : nil)
        }
    }

    /// Synchronous capture for headless use.
    func write(hdr: MTLTexture, to url: URL) -> Bool {
        let commandBuffer = context.makeCommandBuffer(label: "still capture")
        let pixels = encodeReadback(commandBuffer, hdr: hdr)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return Capture.writePNG(pixels, to: url)
    }

    nonisolated static func writePNG(_ pixels: Pixels, to url: URL) -> Bool {
        let width = pixels.width, height = pixels.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let cgContext = CGContext(data: pixels.buffer.contents(), width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
              let image = cgContext.makeImage() else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            return false
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}
