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
    private let spritePass: SpritePass
    private let presentPass: PresentPass
    private let capture: Capture
    private let hudRenderer: HudRenderer
    private var system: ParticleSystem
    private var camera = OrbitCamera()
    private var stats = FrameStats()
    private var paused = false
    private var hudVisible = true
    private var needsSeed = true
    private var screenshotRequested = false
    private var previousFrameTime: Double?
    private var lastCommandBuffer: MTLCommandBuffer?
    private var soak: Soak?
    private let inflight = DispatchSemaphore(value: 3)
    private let maxAllowed: Bool
    private let quitPath: QuitPath

    init(context: GpuContext, view: MTKView, options: Options) {
        self.context = context
        self.view = view
        configuration = Configuration.make(options)
        maxAllowed = configuration.preset == .max
        quitPath = options.quitPath

        if let refusal = context.budget.refusal(bytes: configuration.bytes, describing: "Preset \(configuration.preset.rawValue)") {
            Exit.operational(refusal)
        }
        if configuration.preset.gated {
            Console.line(configuration.preset.thermalNote)
        }

        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .invalid
        view.preferredFramesPerSecond = configuration.fpsCap
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        simPass = SimPass(context: context)
        spritePass = SpritePass(context: context)
        presentPass = PresentPass(context: context, pixelFormat: view.colorPixelFormat)
        capture = Capture(context: context, presentPass: presentPass, pixelFormat: view.colorPixelFormat)
        hudRenderer = HudRenderer(device: context.device)
        system = ParticleSystem(context: context, count: configuration.particles, seed: configuration.seed, potential: .paczynskiWiita)
        if let seconds = options.soakSeconds {
            soak = Soak(start: CACurrentMediaTime(), seconds: seconds)
            stats.recording = true
        }
        spritePass.exposure = Float(Constants.exposure.value)
        super.init()
        spritePass.resize(width: configuration.marchWidth, height: configuration.marchHeight)
    }

    // MARK: MTKViewDelegate

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // The sprite target is sized by the preset, not the window; the
        // present pass scales it to whatever the drawable is.
    }

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { render() }
    }

    private func render() {
        let now = CACurrentMediaTime()
        stats.recordFrame(now: now, previous: previousFrameTime)
        previousFrameTime = now
        if let last = lastCommandBuffer, last.status == .completed {
            stats.recordGpu(seconds: last.gpuEndTime - last.gpuStartTime)
            lastCommandBuffer = nil
        }

        inflight.wait()
        guard let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor, let hdr = spritePass.target else {
            inflight.signal()
            return
        }
        let commandBuffer = context.makeCommandBuffer(label: "frame")
        if needsSeed {
            simPass.encodeSeed(commandBuffer, system: system)
            needsSeed = false
        }
        if !paused {
            simPass.encodeStep(commandBuffer, system: system)
        }
        spritePass.encode(commandBuffer, system: system, camera: camera)
        let scale = view.window?.backingScaleFactor ?? 2
        let hudTexture = hudVisible ? hudRenderer.texture(for: Hud.lines(hudState()), scale: scale) : nil
        presentPass.encode(commandBuffer, pass: pass, hdr: hdr, hudTexture: hudTexture,
                           targetWidth: drawable.texture.width, targetHeight: drawable.texture.height)
        if screenshotRequested {
            screenshotRequested = false
            let finishing = soak?.finishing ?? false
            capture.encode(commandBuffer, hdr: hdr) { url in
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
        lastCommandBuffer = commandBuffer

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
            validation: "not run")
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

    /// Wait for in flight work so the process exits with nothing on the queue.
    func shutdown() {
        view.isPaused = true
        view.delegate = nil
        lastCommandBuffer?.waitUntilCompleted()
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
        case .screenshot:
            screenshotRequested = true
        case .hud:
            hudVisible.toggle()
        case .debug:
            break
        case .presetSmall, .presetDefault, .presetMax:
            break
        }
    }

    func dragged(deltaX: Float, deltaY: Float) {
        camera.orbit(deltaX: deltaX, deltaY: deltaY)
    }

    func scrolled(delta: Float) {
        camera.dolly(delta)
    }
}
