import AppKit

@MainActor
final class PetWindow {
    let window: NSWindow
    let view: PetView
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    var frame: NSRect { window.frame }

    init() {
        let width: CGFloat = 144
        let height: CGFloat = 156
        let margin: CGFloat = 40
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: screen.maxX - width - margin, y: screen.minY + margin)

        let win = NSWindow(
            contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]
        win.ignoresMouseEvents = false
        win.isMovableByWindowBackground = false

        let v = PetView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        v.autoresizingMask = [.width, .height]
        win.contentView = v
        self.window = win
        self.view = v

        v.onClick = { [weak self] in self?.onClick?() }
        v.onDoubleClick = { [weak self] in self?.onDoubleClick?() }
        v.onRightClick = { [weak self] e in self?.onRightClick?(e) }
    }

    func show() {
        window.orderFrontRegardless()
        view.startAnimating()
    }

    func hide() {
        window.orderOut(nil)
    }

    var isVisible: Bool { window.isVisible }

    func setAction(_ a: PetAction) {
        view.setAction(a)
    }

    var currentAction: PetAction { view.currentAction }
}

/// 完整 9 个 sprite 行对应的动作。
/// 行序见 codex-pet.org: 0=待机 1=向右跑 2=向左跑 3=挥手 4=跳跃 5=失败 6=等待 7=奔跑 8=审阅
enum PetAction {
    case idle
    case runRight
    case runLeft
    case wave
    case jump
    case fail
    case wait
    case sprint
    case review
}

@MainActor
final class PetView: NSView {
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    /// 鼠标按下瞬间,鼠标在屏幕上的全局坐标
    private var dragMouseStartScreen: NSPoint?
    /// 鼠标按下瞬间,窗口左下角在屏幕上的位置
    private var dragWindowStartOrigin: NSPoint?
    private var didDrag = false
    private static let dragThreshold: CGFloat = 3

    // Sprite sheet:1536x1872, 8 列 × 9 行,每帧 192x208
    private static let frameW: CGFloat = 192
    private static let frameH: CGFloat = 208
    private static let rowFrames: [Int] = [6, 8, 8, 4, 5, 8, 6, 6, 6]

    private static func row(for a: PetAction) -> Int {
        switch a {
        case .idle:     return 0
        case .runRight: return 1
        case .runLeft:  return 2
        case .wave:     return 3
        case .jump:     return 4
        case .fail:     return 5
        case .wait:     return 6
        case .sprint:   return 7
        case .review:   return 8
        }
    }

    /// 每个动作真正循环用几帧。整行扫一遍常常包含大姿态切换,所以为流畅起见挑能形成循环的前 N 帧。
    private static func activeCols(for a: PetAction) -> Int {
        switch a {
        case .idle:     return 1
        case .runRight: return 8
        case .runLeft:  return 8
        case .wave:     return 4
        case .jump:     return 5
        case .fail:     return 4
        case .wait:     return 3
        case .sprint:   return 6
        case .review:   return 3
        }
    }

    private static func framePeriod(for a: PetAction) -> TimeInterval {
        switch a {
        case .idle:     return 1.0
        case .runRight: return 0.10
        case .runLeft:  return 0.10
        case .wave:     return 0.22
        case .jump:     return 0.14
        case .fail:     return 0.22
        case .wait:     return 0.26
        case .sprint:   return 0.08
        case .review:   return 0.30
        }
    }

    /// 该动作每秒会让窗口水平移动多少像素(正数右,负数左)。
    private static func walkSpeed(for a: PetAction) -> CGFloat {
        switch a {
        case .runRight: return 55
        case .runLeft:  return -55
        case .sprint:   return 95
        default:        return 0
        }
    }

    private let sheet: NSImage?
    private(set) var currentAction: PetAction = .idle
    private var displayCol: Int = 0
    private var animTimer: Timer?
    private var lastTickAt: Date = Date()
    private var frameElapsed: TimeInterval = 0
    private var idleClock: TimeInterval = 0
    private var actionClock: TimeInterval = 0  // 自当前动作开始至今的累计秒

    override init(frame frameRect: NSRect) {
        self.sheet = NSImage(named: "xiao-ikun")
            ?? Bundle.module.image(forResource: NSImage.Name("xiao-ikun"))
        super.init(frame: frameRect)
        if sheet == nil {
            NSLog("[DesktopPet] sprite sheet not found in bundle")
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { false }

    func setAction(_ a: PetAction) {
        guard currentAction != a else { return }
        currentAction = a
        frameElapsed = 0
        actionClock = 0
        let cap = max(1, Self.activeCols(for: a))
        displayCol = min(displayCol, cap - 1)
        needsDisplay = true
    }

    func startAnimating() {
        animTimer?.invalidate()
        lastTickAt = Date()
        frameElapsed = 0
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTickAt)
        lastTickAt = now
        idleClock += dt
        actionClock += dt

        // 跑动:平移窗口
        let vx = Self.walkSpeed(for: currentAction)
        if vx != 0, let win = window {
            let screen = NSScreen.main?.visibleFrame ?? win.frame
            var origin = win.frame.origin
            origin.x += vx * CGFloat(dt)
            // 撞到屏幕边缘就反向
            let minX = screen.minX + 4
            let maxX = screen.maxX - win.frame.width - 4
            if origin.x < minX {
                origin.x = minX
                if currentAction == .runLeft { setAction(.runRight) }
                else if currentAction == .sprint { setAction(.runRight) }
            } else if origin.x > maxX {
                origin.x = maxX
                if currentAction == .runRight { setAction(.runLeft) }
                else if currentAction == .sprint { setAction(.runLeft) }
            }
            win.setFrameOrigin(origin)
        }

        let cols = Self.activeCols(for: currentAction)
        if cols <= 1 {
            if displayCol != 0 { displayCol = 0 }
            needsDisplay = true
            return
        }
        frameElapsed += dt
        if frameElapsed >= Self.framePeriod(for: currentAction) {
            frameElapsed = 0
            displayCol = (displayCol + 1) % cols
            needsDisplay = true
        } else {
            needsDisplay = true
        }
    }

    // MARK: - 鼠标处理

    override func mouseDown(with event: NSEvent) {
        // 用屏幕全局坐标系跟踪拖动:event.locationInWindow 在窗口移动后参考系会变,
        // 导致经典的来回抖动。NSEvent.mouseLocation 始终是屏幕坐标,稳定。
        dragMouseStartScreen = NSEvent.mouseLocation
        dragWindowStartOrigin = window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseStart = dragMouseStartScreen,
              let originStart = dragWindowStartOrigin,
              let win = window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - mouseStart.x
        let dy = now.y - mouseStart.y
        if !didDrag && abs(dx) <= Self.dragThreshold && abs(dy) <= Self.dragThreshold { return }
        didDrag = true
        win.setFrameOrigin(NSPoint(x: originStart.x + dx, y: originStart.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag {
            if event.clickCount >= 2 {
                onDoubleClick?()
            } else {
                onClick?()
            }
        }
        dragMouseStartScreen = nil
        dragWindowStartOrigin = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)

        let W = bounds.width
        let H = bounds.height

        // 地面阴影
        NSColor.black.withAlphaComponent(0.18).setFill()
        let shadowW = W * 0.50
        let shadowH = H * 0.04
        NSBezierPath(ovalIn: NSRect(x: (W - shadowW) / 2, y: 2, width: shadowW, height: shadowH)).fill()

        guard let img = sheet else { return }

        let row = Self.row(for: currentAction)
        let col = max(0, min(displayCol, Self.rowFrames[row] - 1))

        let sheetSize = img.size
        let srcX = CGFloat(col) * Self.frameW
        let srcYFromTop = CGFloat(row) * Self.frameH
        let srcY = sheetSize.height - srcYFromTop - Self.frameH
        let srcRect = NSRect(x: srcX, y: srcY, width: Self.frameW, height: Self.frameH)

        let scale = min(W / Self.frameW, H / Self.frameH)
        let drawW = Self.frameW * scale
        let drawH = Self.frameH * scale

        // 各动作的"上下浮动":idle 是缓慢呼吸,jump 是真正跳起来,跑/sprint 是脚步起伏。
        let bob: CGFloat
        switch currentAction {
        case .idle:
            let period: TimeInterval = 3.0
            let phase = (idleClock.truncatingRemainder(dividingBy: period)) / period
            bob = 1.5 * CGFloat(sin(phase * 2 * .pi))
        case .jump:
            // 整段跳跃 0.7s,抛物线 0 → +18 → 0
            let dur: TimeInterval = 0.7
            let t = min(actionClock, dur) / dur
            bob = 18 * CGFloat(sin(t * .pi))
        case .runRight, .runLeft:
            // 脚步小幅起伏
            let period: TimeInterval = Self.framePeriod(for: currentAction) * 2
            let phase = (actionClock.truncatingRemainder(dividingBy: period)) / period
            bob = 1.5 * CGFloat(abs(sin(phase * 2 * .pi)))
        case .sprint:
            let period: TimeInterval = Self.framePeriod(for: currentAction) * 2
            let phase = (actionClock.truncatingRemainder(dividingBy: period)) / period
            bob = 2.5 * CGFloat(abs(sin(phase * 2 * .pi)))
        case .wave, .wait, .fail, .review:
            let period: TimeInterval = 1.8
            let phase = (idleClock.truncatingRemainder(dividingBy: period)) / period
            bob = 0.6 * CGFloat(sin(phase * 2 * .pi))
        }
        let dstRect = NSRect(x: (W - drawW) / 2, y: 4 + bob, width: drawW, height: drawH)

        img.draw(in: dstRect, from: srcRect, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
    }
}
