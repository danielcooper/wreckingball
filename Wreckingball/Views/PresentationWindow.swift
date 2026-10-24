import AppKit

/// A window containing nothing but the live canvas, so it can be picked as a window to share in
/// Google Meet, Zoom or Slack. The title bar is transparent and its buttons stay hidden until the
/// pointer is inside, so the other end sees the canvas and nothing else.
@MainActor
final class PresentationWindow: NSObject, NSWindowDelegate {
    /// Called when the window is closed from the window itself, so the button can show it as off.
    var onClose: (() -> Void)?

    private var window: NSWindow?

    var isOpen: Bool { window != nil }

    func show(layer: CALayer, aspect: CGSize) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let host = CanvasHostView(layer: layer)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.initialSize(aspect: aspect)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // The title is what the sharing picker in a call shows, even though the window hides it.
        window.title = "Wreckingball Presentation"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .black
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentView = host
        window.contentMinSize = NSSize(width: 480, height: 270)
        window.delegate = self
        window.setFrameAutosaveName("presentation")
        self.window = window

        setAspect(aspect)
        showTitlebarButtons(false)
        host.onHover = { [weak self] inside in self?.showTitlebarButtons(inside) }
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let window else { return }
        self.window = nil
        window.delegate = nil
        window.close()
    }

    /// Keeps the window's shape matching the canvas when the resolution changes.
    func setAspect(_ aspect: CGSize) {
        guard let window, aspect.width > 0, aspect.height > 0 else { return }
        window.contentAspectRatio = NSSize(width: aspect.width, height: aspect.height)
        // contentAspectRatio only constrains later resizes, so correct the current height now.
        let frame = window.contentRect(forFrameRect: window.frame)
        let height = (frame.width * aspect.height / aspect.width).rounded()
        guard abs(height - frame.height) > 0.5 else { return }
        window.setContentSize(NSSize(width: frame.width, height: height))
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        onClose?()
    }

    private func showTitlebarButtons(_ visible: Bool) {
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window?.standardWindowButton(kind)?.isHidden = !visible
        }
    }

    /// Large enough to be worth looking at, but still leaving room for the window being presented.
    private static func initialSize(aspect: CGSize) -> NSSize {
        let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let width = min(aspect.width, screen.width * 0.6)
        return NSSize(width: width.rounded(), height: (width * aspect.height / aspect.width).rounded())
    }
}

/// Hosts the engine's presentation layer and reports when the pointer enters or leaves.
private final class CanvasHostView: NSView {
    var onHover: ((Bool) -> Void)?

    init(layer canvas: CALayer) {
        super.init(frame: .zero)
        layer = canvas
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}
