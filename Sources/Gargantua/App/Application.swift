import AppKit
import MetalKit

/// The window, the menu and the three ways out: Esc, Cmd-Q and ctrl-C.
@MainActor
final class Application: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let options: Options
    private var window: NSWindow?
    private var renderer: Renderer?
    private var signalSources: [DispatchSourceSignal] = []

    private init(options: Options) {
        self.options = options
    }

    static func run(_ options: Options) {
        let app = NSApplication.shared
        let delegate = Application(options: options)
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        delegate.installMenu(app)
        delegate.installSignalHandlers()
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let context = GpuContext()
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
        let width = min(1920, screen.width - 64)
        let height = min(1080, screen.height - 64)
        let frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "gargantua"
        window.delegate = self
        window.center()
        let view = SimulationView(frame: frame, device: context.device)
        let renderer = Renderer(context: context, view: view, options: options)
        view.delegate = renderer
        view.input = renderer
        window.contentView = view
        window.makeFirstResponder(view)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        self.renderer = renderer
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        renderer?.shutdown()
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }

    private func installMenu(_ app: NSApplication) {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit gargantua", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        app.mainMenu = mainMenu
    }

    private func installSignalHandlers() {
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated { NSApplication.shared.terminate(nil) }
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
