import Foundation
import Metal
import Oracle

/// `gargantua --still out.png`: an offline render at any size, tiled across
/// many small command buffers with a progress readout.
@MainActor
enum Still {
    static func render(_ options: Options, path: String) -> Never {
        let context = GpuContext()
        let configuration = Configuration.make(options)
        let width = options.width, height = options.height
        let tile = Int(Constants.stillTile.value)
        let extra = UInt64(width) * UInt64(height) * 12 + UInt64(tile * tile) * 16
        if let refusal = context.budget.refusal(bytes: configuration.bytes + extra, describing: "A \(width) by \(height) still at preset \(configuration.preset.rawValue)") {
            Exit.operational(refusal)
        }
        if configuration.preset.gated {
            Console.line(configuration.preset.thermalNote)
        }

        let simPass = SimPass(context: context)
        let splatPass = SplatPass(context: context)
        let marchPass = MarchPass(context: context)
        let presentPass = PresentPass(context: context, pixelFormat: .bgra8Unorm_srgb)
        let capture = Capture(context: context, presentPass: presentPass, pixelFormat: .bgra8Unorm_srgb)
        let system = ParticleSystem(context: context, count: configuration.particles, seed: configuration.seed, potential: .paczynskiWiita)
        let volume = Volume(context: context, size: configuration.volume)

        let settle = Int(Constants.stillSettleSteps.value) / Int(Constants.simulationSubsteps.value)
        Console.line("settling \(configuration.particles) particles for \(Constants.stillSettleSteps.value) substeps")
        Validate.advance(system, steps: settle, context: context, simPass: simPass, seedFirst: true)

        let splat = context.makeCommandBuffer(label: "still splat")
        volume.encodeClear(splat)
        splatPass.encode(splat, system: system, volume: volume)
        splat.commit()
        splat.waitUntilCompleted()

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: MarchPass.pixelFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        let full = context.makeTexture(descriptor, label: "still image")
        let targets = MarchPass.makeTargets(context: context, width: tile, height: tile, label: "still tile")
        let camera = OrbitCamera()
        let columns = (width + tile - 1) / tile
        let rows = (height + tile - 1) / tile
        Console.line("rendering \(width) by \(height) in \(columns * rows) tiles")
        for row in 0..<rows {
            for column in 0..<columns {
                let origin = (column * tile, row * tile)
                let uniforms = MarchPass.uniforms(camera: camera, width: width, height: height, tileOrigin: origin, settings: .still,
                                                  driftBudget: Constants.driftBudgetStill.value, redshift: true, starSeed: UInt32(truncatingIfNeeded: configuration.seed))
                let commandBuffer = context.makeCommandBuffer(label: "still tile")
                marchPass.encodeImage(commandBuffer, uniforms: uniforms, volume: volume, blackbody: system.blackbody, targets: targets, counters: nil)
                guard let blit = commandBuffer.makeBlitCommandEncoder() else {
                    Exit.operational("Metal could not create the tile copy encoder.")
                }
                let size = MTLSize(width: min(tile, width - origin.0), height: min(tile, height - origin.1), depth: 1)
                blit.copy(from: targets.output, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: size,
                          to: full, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: origin.0, y: origin.1, z: 0))
                blit.endEncoding()
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
            }
            Console.line("row \(row + 1) of \(rows)")
        }

        let url = URL(fileURLWithPath: path)
        guard capture.write(hdr: full, to: url) else {
            Exit.operational("Could not write the still to \(url.path).")
        }
        Console.line("still \(url.path)")
        exit(0)
    }
}
