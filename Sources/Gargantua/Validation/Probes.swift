import Metal
import Oracle
import ShaderTypes

/// Integrates batches of rays on the GPU through the march kernel's probe
/// entry point and returns the results to the CPU.
@MainActor
final class Probes {
    private let context: GpuContext
    private let marchPass: MarchPass
    private let volume: Volume
    private let blackbody: MTLTexture

    init(context: GpuContext, marchPass: MarchPass, volume: Volume, blackbody: MTLTexture) {
        self.context = context
        self.marchPass = marchPass
        self.volume = volume
        self.blackbody = blackbody
    }

    struct Launch {
        let origin: SIMD3<Double>
        let direction: SIMD3<Double>
    }

    func run(_ launches: [Launch], settings: Schwarzschild.Settings) -> [RayProbeResult] {
        let count = launches.count
        let input = context.makeBuffer(bytes: count * MemoryLayout<RayProbe>.stride, label: "probe input", shared: true)
        let output = context.makeBuffer(bytes: count * MemoryLayout<RayProbeResult>.stride, label: "probe output", shared: true)
        let probes = input.contents().bindMemory(to: RayProbe.self, capacity: count)
        for (i, launch) in launches.enumerated() {
            probes[i] = RayProbe(
                origin: packed3(x: Float(launch.origin.x), y: Float(launch.origin.y), z: Float(launch.origin.z)),
                direction: packed3(x: Float(launch.direction.x), y: Float(launch.direction.y), z: Float(launch.direction.z)))
        }
        let uniforms = MarchPass.uniforms(camera: OrbitCamera(), width: 1, height: 1, settings: settings,
                                          driftBudget: 1, redshift: false, starSeed: 0)
        let commandBuffer = context.makeCommandBuffer(label: "probes")
        marchPass.encodeProbes(commandBuffer, probes: input, results: output, count: count, uniforms: uniforms, volume: volume, blackbody: blackbody)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return Array(UnsafeBufferPointer(start: output.contents().bindMemory(to: RayProbeResult.self, capacity: count), count: count))
    }

    /// Launch toward the hole from `radius` on the x axis with impact parameter b.
    static func aimed(radius: Double, impactParameter b: Double) -> Launch {
        let ray = Schwarzschild.launch(radius: radius, impactParameter: b)
        return Launch(origin: ray.position, direction: ray.direction)
    }

    /// A grid of camera rays across the default view.
    static func cameraGrid(camera: OrbitCamera, columns: Int, rows: Int, aspect: Double) -> [Launch] {
        var launches: [Launch] = []
        let tanHalf = Double(tan(camera.fovY * 0.5))
        let origin = SIMD3<Double>(camera.position)
        let right = SIMD3<Double>(camera.right), up = SIMD3<Double>(camera.up), forward = SIMD3<Double>(camera.forward)
        for row in 0..<rows {
            for column in 0..<columns {
                let x = (2.0 * (Double(column) + 0.5) / Double(columns) - 1.0) * tanHalf * aspect
                let y = (1.0 - 2.0 * (Double(row) + 0.5) / Double(rows)) * tanHalf
                let d = forward + x * right + y * up
                launches.append(Launch(origin: origin, direction: d / (d * d).sum().squareRoot()))
            }
        }
        return launches
    }
}

extension SIMD3 where Scalar == Double {
    init(_ f: SIMD3<Float>) {
        self.init(Double(f.x), Double(f.y), Double(f.z))
    }
}
