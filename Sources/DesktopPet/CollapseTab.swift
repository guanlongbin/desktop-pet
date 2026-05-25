import AppKit

@MainActor
final class CollapseTab {
    private var window: NSWindow?
    var onClick: (() -> Void)?

    func show() {
        if window == nil { build() }
        positionToBottomRight()
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func positionToBottomRight() {
        guard let win = window else { return }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = win.frame.size
        let origin = NSPoint(x: screen.maxX - size.width, y: screen.minY + 80)
        win.setFrameOrigin(origin)
    }

    private func build() {
        let w: CGFloat = 14
        let h: CGFloat = 56
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating
        win.hasShadow = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]
        win.ignoresMouseEvents = false

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 6
        effect.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor
        effect.autoresizingMask = [.width, .height]

        let view = TabClickView(frame: effect.bounds)
        view.autoresizingMask = [.width, .height]
        view.onClick = { [weak self] in self?.onClick?() }
        effect.addSubview(view)

        win.contentView = effect
        self.window = win
    }
}

@MainActor
private final class TabClickView: NSView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        let dotColor = NSColor(white: 0.95, alpha: 0.85)
        dotColor.setFill()
        let r: CGFloat = 2.5
        let cx = bounds.midX
        let spacing: CGFloat = 7
        for i in 0..<3 {
            let cy = bounds.midY + spacing * CGFloat(i - 1)
            NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: r*2, height: r*2)).fill()
        }
    }
}
