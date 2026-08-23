import AppKit
import MetalKit
import Oracle
import QuartzCore

/// Runs the passes once per vsync and owns the interactive state. Delegate
/// callbacks arrive on the main thread; they hop onto the main actor.
@MainActor
final class Renderer: NSObject, MTKViewDelegate, InputHandler {
    private struct Soak {
        let start: Double
        let seconds: Double
        var finishing = false
    }

    private let context: GpuContext
    private let view: MTKView
    private var configuration: Configuration
    private let simPass: SimPass
    private let splatPass: SplatPass
    private let marchPass: MarchPass
    private let bakePass: BakePass?
    private let presentPass: PresentPass
    private var volume: Volume
    private var upscaler: Upscaler?
    private var previousCamera: OrbitCamera?
    private var frameIndex = 0
    private var walkedLastFrame = false
    private var upscaleWanted: Bool
    private let capture: Capture
    private let hudRenderer: HudRenderer
    private var system: ParticleSystem
    private var camera: OrbitCamera
    private var stats = FrameStats()
    private var paused = false
    private var hudVisible = true
    private var needsSeed = true
    private var validation = "pending"
    private var screenshotRequested = false
    private var previousFrameTime: Double?
    private var recentCommandBuffers: [MTLCommandBuffer] = []
    private var soak: Soak?
    private let inflight = DispatchSemaphore(value: 3)
    private let maxAllowed: Bool
    private let quitPath: QuitPath

    init(context: GpuContext, view: MTKView, options: Options, estimatedDrawable: (Int, Int)) {
        self.context = context
        self.view = view
        configuration = Configuration.make(options)
        camera = OrbitCamera.from(options)
        maxAllowed = configuration.preset == .max
        quitPath = options.quitPath
        upscaleWanted = options.upscale

        if let refusal = context.budget.refusal(bytes: configuration.bytes, describing: "Preset \(configuration.preset.rawValue)") {
            Exit.operational(refusal)
        }
        if configuration.preset.gated {
            Console.line(configuration.preset.thermalNote)
        }
        if configuration.spin > 0, configuration.strategy == .bake {
            Exit.usage("The bake strategy does not support spin yet; use the march strategy.")
        }

        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .invalid
        view.preferredFramesPerSecond = configuration.fpsCap
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        simPass = SimPass(context: context)
        splatPass = SplatPass(context: context)
        marchPass = MarchPass(context: context)
        bakePass = configuration.strategy == .bake ? BakePass(context: context) : nil
        presentPass = PresentPass(context: context, pixelFormat: view.colorPixelFormat)
        volume = Volume(context: context, size: configuration.volume)
        capture = Capture(context: context, presentPass: presentPass, pixelFormat: view.colorPixelFormat)
        hudRenderer = HudRenderer(device: context.device)
        system = ParticleSystem(context: context, count: configuration.particles, seed: configuration.seed, potential: .paczynskiWiita)
        if let seconds = options.soakSeconds {
            soak = Soak(start: CACurrentMediaTime(), seconds: seconds)
            stats.recording = true
        }
        presentPass.exposure = Float(Constants.exposure.value)
        super.init()
        marchPass.resize(width: configuration.marchWidth, height: configuration.marchHeight)
        bakePass?.resize(width: configuration.marchWidth, height: configuration.marchHeight)
        rebuildUpscaler(width: estimatedDrawable.0, height: estimatedDrawable.1)
        let clear = context.makeCommandBuffer(label: "clear volume")
        volume.encodeClear(clear)
        clear.commit()
    }

    // MARK: MTKViewDelegate

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // The march target is sized by the preset, not the window; the
        // upscaler or the present pass takes it to the drawable.
        MainActor.assumeIsolated { rebuildUpscaler(width: Int(size.width), height: Int(size.height)) }
    }

    private func rebuildUpscaler(width: Int, height: Int) {
        guard upscaleWanted, width > 0, height > 0 else { upscaler = nil; return }
        if let upscaler, upscaler.outputWidth == width, upscaler.outputHeight == height,
           upscaler.inputWidth == configuration.marchWidth, upscaler.inputHeight == configuration.marchHeight { return }
        upscaler = Upscaler(context: context, inputWidth: configuration.marchWidth, inputHeight: configuration.marchHeight, outputWidth: width, outputHeight: height)
        if upscaler == nil {
            Console.line("MetalFX temporal upscaling is not available on this device; presenting the march resolution directly.")
            upscaleWanted = false
        }
    }

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { render() }
    }

    private func render() {
        let now = CACurrentMediaTime()
        stats.recordFrame(now: now, previous: previousFrameTime)
        previousFrameTime = now
        for buffer in recentCommandBuffers where buffer.status == .completed {
            stats.recordGpu(seconds: buffer.gpuEndTime - buffer.gpuStartTime)
        }
        recentCommandBuffers.removeAll { $0.status == .completed || $0.status == .error }

        inflight.wait()
        guard let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor, let hdr = marchPass.output else {
            inflight.signal()
            return
        }
        let counters = marchPass.readCounters()
        if counters.rays > 0 {
            let percent = 100.0 * Double(counters.overDriftBudget) / Double(counters.rays)
            validation = String(format: "drift over budget %.2f percent, %u exhausted, %u captured", percent, counters.exhausted, counters.captured)
        }
        let commandBuffer = context.makeCommandBuffer(label: "frame")
        if needsSeed {
            simPass.encodeSeed(commandBuffer, system: system)
            needsSeed = false
        }
        if !paused {
            simPass.encodeStep(commandBuffer, system: system)
        }
        splatPass.encode(commandBuffer, system: system, volume: volume)
        if upscaler == nil, upscaleWanted {
            rebuildUpscaler(width: drawable.texture.width, height: drawable.texture.height)
        }
        // The bake strategy walks stored samples while the camera holds
        // still, marches while it moves, and rebakes progressively once it
        // stops. Walked frames carry no jitter, so the upscaler simply
        // accumulates them.
        let cameraMoved = previousCamera != nil && previousCamera != camera
        var walking = false
        if let bakePass {
            if cameraMoved { bakePass.invalidate() }
            if bakePass.complete, bakePass.bakedCamera == camera { walking = true }
        }
        let jitter = (upscaler != nil && !walking) ? Jitter.offset(frame: frameIndex) : SIMD2<Float>(0, 0)
        frameIndex += 1
        let uniforms = MarchPass.uniforms(camera: camera, jitter: jitter, width: hdr.width, height: hdr.height,
                                          settings: .interactive, driftBudget: Constants.driftBudgetInteractive.value, redshift: true,
                                          starSeed: UInt32(truncatingIfNeeded: system.seed),
                                          bakeSpacing: bakePass?.spacing(volumeSize: volume.size) ?? 0, tables: marchPass.tables,
                                          spin: configuration.spin)
        previousCamera = camera
        if walking, let bakePass, let targets = marchPass.targets {
            bakePass.encodeWalk(commandBuffer, uniforms: uniforms, volume: volume, blackbody: system.blackbody, targets: targets)
            if !walkedLastFrame { upscaler?.reset() }
        } else {
            marchPass.encodeFrame(commandBuffer, uniforms: uniforms, volume: volume, blackbody: system.blackbody)
            if let bakePass, !cameraMoved, !bakePass.complete {
                var bakeUniforms = uniforms
                bakeUniforms.jitter = SIMD2(0, 0)
                bakeUniforms.geodesic = MarchPass.settings(.still)
                bakePass.encodeBakeChunk(commandBuffer, camera: camera, uniforms: bakeUniforms, tables: marchPass.tables)
            }
            if walkedLastFrame { upscaler?.reset() }
        }
        walkedLastFrame = walking
        var presented = hdr
        if let upscaler, let depth = marchPass.depth, let motion = marchPass.motion {
            upscaler.encode(commandBuffer, color: hdr, depth: depth, motion: motion, jitter: jitter)
            presented = upscaler.output
        }
        let scale = view.window?.backingScaleFactor ?? 2
        let hudTexture = hudVisible ? hudRenderer.texture(for: Hud.lines(hudState()), scale: scale) : nil
        presentPass.encode(commandBuffer, pass: pass, hdr: presented, debug: marchPass.debug, hudTexture: hudTexture,
                           targetWidth: drawable.texture.width, targetHeight: drawable.texture.height)
        if screenshotRequested {
            screenshotRequested = false
            let finishing = soak?.finishing ?? false
            capture.encodeScreenshot(commandBuffer, hdr: presented) { url in
                Task { @MainActor in
                    Console.line(url.map { "screenshot \($0.path)" } ?? "screenshot failed to write")
                    if finishing { self.quit() }
                }
            }
        }
        commandBuffer.present(drawable)
        let semaphore = inflight
        commandBuffer.addCompletedHandler { _ in semaphore.signal() }
        commandBuffer.commit()
        recentCommandBuffers.append(commandBuffer)

        if var run = soak, !run.finishing, now - run.start >= run.seconds {
            run.finishing = true
            soak = run
            for line in stats.summary(seconds: now - run.start, targetFps: configuration.fpsCap) {
                Console.line(line)
            }
            screenshotRequested = true
        }
    }

    private func hudState() -> HudState {
        HudState(
            preset: configuration.preset.rawValue,
            particles: configuration.particles,
            seed: system.seed,
            fps: stats.fps,
            cpuMilliseconds: stats.cpuDisplayed * 1000,
            gpuMilliseconds: stats.gpuDisplayed * 1000,
            paused: paused,
            gpuErrors: stats.gpuErrors,
            validation: validation,
            renderer: rendererDescription())
    }

    /// End a soak through the requested path. The key paths inject a real
    /// event into the application so the responder chain and the menu key
    /// equivalent run exactly as they do for a person at the keyboard.
    private func quit() {
        let app = NSApplication.shared
        switch quitPath {
        case .direct:
            app.terminate(nil)
        case .escape, .menu:
            let escape = quitPath == .escape
            let characters = escape ? "\u{1B}" : "q"
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: escape ? [] : [.command],
                                               timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: view.window?.windowNumber ?? 0, context: nil,
                                               characters: characters, charactersIgnoringModifiers: characters,
                                               isARepeat: false, keyCode: escape ? 53 : 12) else {
                Exit.operational("Could not synthesize the \(quitPath.rawValue) key event.")
            }
            Console.line("quitting through \(quitPath.rawValue)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                Exit.fail("The \(self.quitPath.rawValue) quit path did not end the program within two seconds.", code: 1)
            }
            app.sendEvent(event)
        }
    }

    private func rendererDescription() -> String {
        var march = "march \(configuration.marchWidth) by \(configuration.marchHeight)"
        if configuration.spin > 0 {
            march += String(format: ", spin %.3f", configuration.spin)
        }
        if let bakePass {
            march = walkedLastFrame ? "walk of \(configuration.marchWidth) by \(configuration.marchHeight) bake (\(bakePass.overflowCount) rays over budget)" : "march \(configuration.marchWidth) by \(configuration.marchHeight), baking \(bakePass.bakedRows) of \(bakePass.height) rows"
        }
        if let upscaler {
            return "\(march), metalfx temporal to \(upscaler.outputWidth) by \(upscaler.outputHeight)"
        }
        return "\(march), native"
    }

    /// Switch presets live. A preset that fails the budget, or the gated max
    /// preset without its launch flag, is refused in one sentence and the
    /// program stays where it is.
    private func switchPreset(_ preset: Preset) {
        guard preset != configuration.preset else { return }
        if preset.gated && !maxAllowed {
            Console.line("The max preset runs only when the program is launched with --preset max. " + preset.thermalNote)
            return
        }
        let next = configuration.with(preset: preset)
        if let refusal = context.budget.refusal(bytes: next.bytes, describing: "Preset \(preset.rawValue)") {
            Console.line(refusal)
            return
        }
        recentCommandBuffers.last?.waitUntilCompleted()
        configuration = next
        system = ParticleSystem(context: context, count: next.particles, seed: system.seed, potential: .paczynskiWiita)
        volume = Volume(context: context, size: next.volume)
        marchPass.resize(width: next.marchWidth, height: next.marchHeight)
        bakePass?.resize(width: next.marchWidth, height: next.marchHeight)
        upscaler = nil
        let clear = context.makeCommandBuffer(label: "clear volume")
        volume.encodeClear(clear)
        clear.commit()
        needsSeed = true
        Console.line("preset \(preset.rawValue): \(next.particles) particles, \(next.volume) cubed volume, \(next.marchWidth) by \(next.marchHeight) march")
    }

    /// Wait for in flight work so the process exits with nothing on the queue.
    func shutdown() {
        view.isPaused = true
        view.delegate = nil
        recentCommandBuffers.last?.waitUntilCompleted()
    }

    // MARK: InputHandler

    func keyPressed(_ key: Key) {
        switch key {
        case .escape:
            NSApplication.shared.terminate(nil)
        case .space:
            paused.toggle()
        case .reseed:
            system.reseed(system.seed &+ 1)
            needsSeed = true
            upscaler?.reset()
        case .screenshot:
            screenshotRequested = true
        case .hud:
            hudVisible.toggle()
        case .debug:
            presentPass.debugView.toggle()
        case .presetSmall:
            switchPreset(.small)
        case .presetDefault:
            switchPreset(.standard)
        case .presetMax:
            switchPreset(.max)
        }
    }

    func dragged(deltaX: Float, deltaY: Float) {
        camera.orbit(deltaX: deltaX, deltaY: deltaY)
    }

    func scrolled(delta: Float) {
        camera.dolly(delta)
    }
}
