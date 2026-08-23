import AppKit
import Metal

/// Rasterizes hud text into a texture with CoreText. Re-rasterizes only when
/// the text changes.
@MainActor
final class HudRenderer {
    private let device: MTLDevice
    private var cachedLines: [String] = []
    private var cachedScale: CGFloat = 0
    private var cached: MTLTexture?

    init(device: MTLDevice) {
        self.device = device
    }

    func texture(for lines: [String], scale: CGFloat) -> MTLTexture? {
        if lines == cachedLines, scale == cachedScale, let cached { return cached }
        let font = NSFont.monospacedSystemFont(ofSize: 12 * scale, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let strings = lines.map { NSAttributedString(string: $0, attributes: attributes) }
        let padding = 10 * scale
        let lineHeight = ceil(font.ascender - font.descender + font.leading) + 2 * scale
        let textWidth = strings.map { ceil($0.size().width) }.max() ?? 0
        let width = max(Int(textWidth + 2 * padding), 8)
        let height = max(Int(lineHeight * CGFloat(lines.count) + 2 * padding), 8)

        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            return nil
        }
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for (index, string) in strings.enumerated() {
            let y = CGFloat(height) - padding - lineHeight * CGFloat(index + 1) + 2 * scale
            string.draw(at: NSPoint(x: padding, y: y))
        }
        NSGraphicsContext.restoreGraphicsState()

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor), let data = context.data else { return nil }
        texture.label = "hud"
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: data, bytesPerRow: width * 4)
        cachedLines = lines
        cachedScale = scale
        cached = texture
        return texture
    }
}
