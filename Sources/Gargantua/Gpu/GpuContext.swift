import Metal
import Oracle

/// Owns the device, the queue and the compiled shader libraries. Shaders are
/// compiled from source by the runtime Metal compiler once per process and
/// kept in memory; nothing is written to disk.
@MainActor
final class GpuContext {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let budget: MemoryBudget
    private var libraries: [String: MTLLibrary] = [:]
    private(set) var commandBuffersCompleted: UInt64 = 0

    init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Exit.operational("No Metal device is available on this machine.")
        }
        guard let queue = device.makeCommandQueue() else {
            Exit.operational("Metal could not create a command queue.")
        }
        self.device = device
        self.queue = queue
        self.budget = MemoryBudget(device: device)
        queue.label = "gargantua"
    }

    /// Compile a translation unit. Integrators and simulation use precise
    /// math; shading can use fast math.
    func library(_ unit: String, preciseMath: Bool) -> MTLLibrary {
        if let cached = libraries[unit] { return cached }
        let options = MTLCompileOptions()
        options.languageVersion = .version3_1
        if #available(macOS 15.0, *) {
            options.mathMode = preciseMath ? .safe : .fast
        } else {
            options.setValue(!preciseMath, forKey: "fastMathEnabled")
        }
        let source = ShaderSource.assemble(unit)
        do {
            let library = try device.makeLibrary(source: source, options: options)
            library.label = unit
            libraries[unit] = library
            return library
        } catch {
            Exit.operational("Shader \(unit) failed to compile: \(error.localizedDescription)")
        }
    }

    func function(_ unit: String, _ name: String, preciseMath: Bool) -> MTLFunction {
        guard let function = library(unit, preciseMath: preciseMath).makeFunction(name: name) else {
            Exit.operational("Shader \(unit) has no function named \(name).")
        }
        return function
    }

    func computePipeline(_ unit: String, _ name: String, preciseMath: Bool = true) -> MTLComputePipelineState {
        do {
            return try device.makeComputePipelineState(function: function(unit, name, preciseMath: preciseMath))
        } catch {
            Exit.operational("Compute pipeline \(name) failed to build: \(error.localizedDescription)")
        }
    }

    func renderPipeline(_ descriptor: MTLRenderPipelineDescriptor) -> MTLRenderPipelineState {
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            Exit.operational("Render pipeline \(descriptor.label ?? "unnamed") failed to build: \(error.localizedDescription)")
        }
    }

    /// A command buffer whose completion status is always checked. A failed
    /// buffer ends the program with one sentence; nothing is resubmitted.
    func makeCommandBuffer(label: String) -> MTLCommandBuffer {
        guard let buffer = queue.makeCommandBuffer() else {
            Exit.operational("Metal could not create a command buffer.")
        }
        buffer.label = label
        buffer.addCompletedHandler { completed in
            if completed.status == .error {
                let reason = completed.error?.localizedDescription ?? "unknown error"
                Exit.operational("GPU command buffer \(label) failed: \(reason)")
            }
        }
        return buffer
    }

    func makeBuffer(bytes: Int, label: String, shared: Bool = false) -> MTLBuffer {
        guard let buffer = device.makeBuffer(length: max(bytes, 16), options: shared ? .storageModeShared : .storageModePrivate) else {
            Exit.operational("Metal could not allocate \(formatBytes(UInt64(bytes))) for \(label).")
        }
        buffer.label = label
        return buffer
    }

    func makeTexture(_ descriptor: MTLTextureDescriptor, label: String) -> MTLTexture {
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            Exit.operational("Metal could not allocate the \(label) texture.")
        }
        texture.label = label
        return texture
    }
}
