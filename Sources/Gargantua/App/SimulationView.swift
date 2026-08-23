import AppKit
import MetalKit

enum Key {
    case escape, space, reseed, screenshot, hud, debug, presetSmall, presetDefault, presetMax
}

@MainActor
protocol InputHandler: AnyObject {
    func keyPressed(_ key: Key)
    func dragged(deltaX: Float, deltaY: Float)
    func scrolled(delta: Float)
}

/// The Metal view plus the keyboard and mouse mapping from the spec.
final class SimulationView: MTKView {
    weak var input: InputHandler?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { input?.keyPressed(.escape); return }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case " ": input?.keyPressed(.space)
        case "r": input?.keyPressed(.reseed)
        case "s": input?.keyPressed(.screenshot)
        case "h": input?.keyPressed(.hud)
        case "d": input?.keyPressed(.debug)
        case "1": input?.keyPressed(.presetSmall)
        case "2": input?.keyPressed(.presetDefault)
        case "3": input?.keyPressed(.presetMax)
        default: super.keyDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        input?.dragged(deltaX: Float(event.deltaX), deltaY: Float(event.deltaY))
    }

    override func scrollWheel(with event: NSEvent) {
        input?.scrolled(delta: Float(event.scrollingDeltaY))
    }
}
