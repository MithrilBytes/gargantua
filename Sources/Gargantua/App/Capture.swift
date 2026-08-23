import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

/// Reads a rendered frame back and writes a PNG to ~/Pictures/gargantua/.
/// The only disk write in interactive use, and only when asked for.
@MainActor
final class Capture {
    private struct Pixels: @unchecked Sendable {
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

    static func nextPath() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return directory.appending(path: "gargantua-\(formatter.string(from: Date())).png")
    }

    /// Encode a hud free present into an offscreen target and copy it to
    /// host memory. The completion runs off the main thread once the GPU is
    /// done, with the path written or nil on failure.
    func encode(_ commandBuffer: MTLCommandBuffer, hdr: MTLTexture, completion: @escaping @Sendable (URL?) -> Void) {
        let width = hdr.width, height = hdr.height
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let target = context.makeTexture(descriptor, label: "screenshot")
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        presentPass.encode(commandBuffer, pass: pass, hdr: hdr, hudTexture: nil, targetWidth: width, targetHeight: height)

        let buffer = context.makeBuffer(bytes: width * height * 4, label: "screenshot readback", shared: true)
        guard let blit = commandBuffer.makeBlitCommandEncoder() else {
            Exit.operational("Metal could not create the screenshot blit encoder.")
        }
        blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: buffer, destinationOffset: 0, destinationBytesPerRow: width * 4, destinationBytesPerImage: width * height * 4)
        blit.endEncoding()

        let pixels = Pixels(buffer: buffer, width: width, height: height)
        let path = Capture.nextPath()
        commandBuffer.addCompletedHandler { _ in
            completion(Capture.writePNG(pixels, to: path) ? path : nil)
        }
    }

    nonisolated private static func writePNG(_ pixels: Pixels, to url: URL) -> Bool {
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
