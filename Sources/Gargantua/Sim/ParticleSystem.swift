import Foundation
import Metal
import Oracle
import ShaderTypes

/// GPU resident particle state plus the two small tables the kernels read.
@MainActor
final class ParticleSystem {
    let count: Int
    let potential: Potential
    let buffer: MTLBuffer
    let inverseCdf: MTLBuffer
    let blackbody: MTLTexture
    private(set) var seed: UInt64
    private(set) var steps: UInt64 = 0

    init(context: GpuContext, count: Int, seed: UInt64, potential: Potential) {
        self.count = count
        self.seed = seed
        self.potential = potential
        buffer = context.makeBuffer(bytes: count * Int(Configuration.particleStride), label: "particles")

        let table = DiskModel.radialInverseCdf(count: Configuration.inverseCdfCount).map(Float.init)
        let cdfBuffer = context.makeBuffer(bytes: table.count * 4, label: "seeding table", shared: true)
        table.withUnsafeBytes { cdfBuffer.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        inverseCdf = cdfBuffer

        let colors = Blackbody.table()
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type1D
        descriptor.pixelFormat = .rgba16Float
        descriptor.width = colors.count
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        let colorTexture = context.makeTexture(descriptor, label: "blackbody table")
        var pixels = [Float16]()
        pixels.reserveCapacity(colors.count * 4)
        for color in colors {
            pixels.append(Float16(color.x))
            pixels.append(Float16(color.y))
            pixels.append(Float16(color.z))
            pixels.append(1.0)
        }
        pixels.withUnsafeBytes {
            colorTexture.replace(region: MTLRegionMake1D(0, colors.count), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: $0.count)
        }
        blackbody = colorTexture
    }

    func reseed(_ seed: UInt64) {
        self.seed = seed
        steps = 0
    }

    func recordStep() {
        steps += 1
    }

    var uniforms: SimUniforms {
        let floor = Constants.zeroTorqueFloor.value
        let peakShape = pow(DiskModel.isco / DiskModel.peakRadius, 0.75) * pow(max(1.0 - (DiskModel.isco / DiskModel.peakRadius).squareRoot(), floor), 0.25)
        return SimUniforms(
            seed: SIMD2(UInt32(truncatingIfNeeded: seed), UInt32(truncatingIfNeeded: seed >> 32)),
            particleCount: UInt32(count),
            potential: potential == .paczynskiWiita ? UInt32(PotentialPaczynskiWiita) : UInt32(PotentialNewtonian),
            inverseCdfCount: UInt32(Configuration.inverseCdfCount),
            dt: Float(Constants.simulationTimestep.value),
            alpha: Float(Constants.dragAlpha.value),
            temperatureScale: Float(Constants.peakTemperature.value / peakShape))
    }
}

