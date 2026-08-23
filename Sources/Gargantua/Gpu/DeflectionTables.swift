import Metal
import Oracle
import ShaderTypes

/// The three sweep tables the march looks bending up from outside the
/// integration sphere: from the sphere to infinity, from the camera to
/// infinity, and the full turn of rays that never enter the sphere. The
/// sphere table is fixed; the other two follow the camera radius.
@MainActor
final class DeflectionTables {
    static let count = Int(Constants.sweepTableSize.value)
    static let intervals = 256

    let sphereRadius: Double
    let sphere: MTLTexture
    let camera: MTLTexture
    let sky: MTLTexture
    private(set) var cameraRadius: Double = 0
    let sphereMaxB: Float
    private(set) var cameraMaxB: Float = 0
    let skyMinB: Float
    private(set) var skyMaxB: Float = 0

    /// Rays whose periapsis lies outside this radius never enter; it sits one
    /// unit inside the sphere so no ray is placed on the sphere grazing it,
    /// where the radial velocity would come from a cancellation.
    let entryRadius: Double

    init(context: GpuContext, sphereRadius: Double = Constants.volumeHalfExtent.value) {
        self.sphereRadius = sphereRadius
        entryRadius = sphereRadius - 1.0
        sphereMaxB = Float(Deflection.maximumImpactParameter(atRadius: entryRadius))
        skyMinB = sphereMaxB
        func make(_ label: String) -> MTLTexture {
            let descriptor = MTLTextureDescriptor()
            descriptor.textureType = .type1D
            descriptor.pixelFormat = .r32Float
            descriptor.width = DeflectionTables.count
            descriptor.usage = .shaderRead
            descriptor.storageMode = .shared
            return context.makeTexture(descriptor, label: label)
        }
        sphere = make("sphere sweep")
        camera = make("camera sweep")
        sky = make("sky sweep")
        DeflectionTables.fill(sphere, Deflection.sweepTable(fromRadius: sphereRadius, count: DeflectionTables.count))
    }

    private static func fill(_ texture: MTLTexture, _ values: [Double]) {
        let floats = values.map(Float.init)
        floats.withUnsafeBytes {
            texture.replace(region: MTLRegionMake1D(0, floats.count), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: $0.count)
        }
    }

    /// Recompute the camera dependent tables when the camera radius moves.
    func update(cameraRadius radius: Double) {
        guard abs(radius - cameraRadius) > 1e-6 else { return }
        cameraRadius = radius
        cameraMaxB = Float(Deflection.maximumImpactParameter(atRadius: radius))
        skyMaxB = cameraMaxB
        DeflectionTables.fill(camera, Deflection.sweepTable(fromRadius: radius, count: DeflectionTables.count, intervals: DeflectionTables.intervals))
        DeflectionTables.fill(sky, Deflection.skyTable(cameraRadius: radius, sphereRadius: entryRadius, count: DeflectionTables.count, intervals: DeflectionTables.intervals))
    }

    /// Enable the jump in a set of uniforms. Without this call the march
    /// integrates every ray from the camera to the escape radius.
    func apply(to uniforms: inout MarchUniforms) {
        uniforms.sphereRadius = Float(sphereRadius)
        uniforms.cameraRadius = Float(cameraRadius)
        uniforms.sphereMaxB = sphereMaxB
        uniforms.sphereTableMaxB = Float(Deflection.maximumImpactParameter(atRadius: sphereRadius))
        uniforms.cameraMaxB = cameraMaxB
        uniforms.skyMinB = skyMinB
        uniforms.skyMaxB = skyMaxB
    }

    func bind(_ encoder: MTLComputeCommandEncoder) {
        encoder.setTexture(sphere, index: 7)
        encoder.setTexture(camera, index: 8)
        encoder.setTexture(sky, index: 9)
    }
}
