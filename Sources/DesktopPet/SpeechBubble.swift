import AppKit

/// 宠物头顶冒的气泡。
/// - 视觉:磨砂玻璃(NSVisualEffectView .popover)+ 形状阴影 + 圆滑尖角,深浅色自适应。
/// - 文字:真流式。先 show(),然后由调用方一段一段 append(),
///   不再用本地 Timer 模拟"打字机"。
///   show 也支持 initialText/最终回退用的 fallback。
@MainActor
final class SpeechBubble {
    private var window: NSWindow?
    private var hideTimer: Timer?
    private var thinkingTimer: Timer?
    private var thinkingDots: Int = 1
    private var receivedAnyChunk = false
    private weak var view: BubbleView?

    /// 开启一个空气泡,后续用 append() 往里塞字。
    /// streamingFallback: 8 秒内一个字都没塞进来时显示的兜底文案。
    func beginStream(anchorWindowFrame: NSRect, streamingFallback: String) {
        present(text: "想…", anchorWindowFrame: anchorWindowFrame)
        startThinkingAnimation()
        scheduleFallback(text: streamingFallback, after: 8.0)
    }

    /// 一次性显示完整文本(非流式,用于 SolarTerm/Countdown 这种本地文案)。
    func show(text: String, anchorWindowFrame: NSRect, duration: TimeInterval = 6.5) {
        present(text: text, anchorWindowFrame: anchorWindowFrame)
        scheduleAutoDismiss(after: duration)
    }

    /// 流式追加。在 beginStream() 之后调用。
    func append(_ chunk: String) {
        guard let view = view, let win = window else { return }
        if !receivedAnyChunk {
            receivedAnyChunk = true
            stopThinkingAnimation()
            view.replaceText(with: "")
        }
        view.append(chunk)
        // 字数变了,可能需要扩大气泡。重排版。
        relayout(window: win, view: view)
        hideTimer?.invalidate()  // 收到新字就重新计时
    }

    /// 流结束。从最后一个 token 起,按可读时长再停一会。
    func endStream(minVisibleAfterEnd: TimeInterval = 4.5) {
        guard let view = view else { return }
        let readTime = max(minVisibleAfterEnd, Double(view.currentTextCount) * 0.10)
        scheduleAutoDismiss(after: readTime)
    }

    /// 流出错。用兜底文案替换显示。
    func failStream(fallback: String) {
        stopThinkingAnimation()
        receivedAnyChunk = true
        guard let view = view, let win = window else { return }
        view.replaceText(with: fallback)
        relayout(window: win, view: view)
        scheduleAutoDismiss(after: 5.0)
    }

    func dismiss() {
        hideTimer?.invalidate()
        hideTimer = nil
        stopThinkingAnimation()
        guard let win = window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            win.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                win.orderOut(nil)
                if self?.window === win { self?.window = nil }
            }
        })
    }

    // MARK: - 内部

    private func present(text: String, anchorWindowFrame: NSRect) {
        hideTimer?.invalidate()
        stopThinkingAnimation()
        receivedAnyChunk = false
        if let old = window { old.orderOut(nil); window = nil }

        let win = makeWindow(anchorWindowFrame: anchorWindowFrame)
        let v = win.contentView as! BubbleView
        v.replaceText(with: text)
        v.onClick = { [weak self] in self?.dismiss() }
        v.setup()
        self.view = v
        self.window = win

        win.alphaValue = 0
        win.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            win.animator().alphaValue = 1
        }
    }

    private func scheduleAutoDismiss(after seconds: TimeInterval) {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    private func scheduleFallback(text: String, after seconds: TimeInterval) {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, !self.receivedAnyChunk else { return }
                self.failStream(fallback: text)
            }
        }
    }

    private func startThinkingAnimation() {
        thinkingTimer?.invalidate()
        thinkingDots = 1
        thinkingTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, let v = self.view, let win = self.window else { return }
                if self.receivedAnyChunk { return }
                self.thinkingDots = (self.thinkingDots % 3) + 1
                let dots = String(repeating: "·", count: self.thinkingDots)
                v.replaceText(with: "想\(dots)")
                self.relayout(window: win, view: v)
            }
        }
    }

    private func stopThinkingAnimation() {
        thinkingTimer?.invalidate()
        thinkingTimer = nil
    }

    /// 用最新的 fullText 计算气泡需要多大,然后调整 window/view/layer。
    private func relayout(window: NSWindow, view: BubbleView) {
        let layout = BubbleLayout.compute(text: view.fullText)
        let shadowMargin = layout.shadowMargin
        let totalW = layout.totalW
        let totalH = layout.totalH
        let containerW = totalW + shadowMargin * 2
        let containerH = totalH + shadowMargin * 2

        // 保持气泡尖角相对屏幕的锚点不变(以原 anchorCenterX 为准)
        let anchorCenterX = view.anchorCenterX
        let petTopY = view.anchorTopY
        var origin = NSPoint(
            x: anchorCenterX - totalW / 2 - shadowMargin,
            y: petTopY + 6 - shadowMargin
        )
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if origin.x + shadowMargin < screen.minX + 4 {
            origin.x = screen.minX + 4 - shadowMargin
        }
        if origin.x + shadowMargin + totalW > screen.maxX - 4 {
            origin.x = screen.maxX - 4 - totalW - shadowMargin
        }
        window.setFrame(NSRect(origin: origin, size: NSSize(width: containerW, height: containerH)), display: true)

        view.frame = NSRect(x: 0, y: 0, width: containerW, height: containerH)
        view.bubbleFrame = NSRect(x: shadowMargin, y: shadowMargin, width: totalW, height: totalH)
        view.bubbleHeight = layout.bubbleH
        view.tailHeight = layout.tailH
        let tailX = anchorCenterX - origin.x
        view.tailCenterX = max(shadowMargin + 22, min(shadowMargin + totalW - 22, tailX))
        view.applyLayout()
    }

    private func makeWindow(anchorWindowFrame: NSRect) -> NSWindow {
        let layout = BubbleLayout.compute(text: "")
        let shadowMargin = layout.shadowMargin
        let totalW = layout.totalW
        let totalH = layout.totalH
        let containerW = totalW + shadowMargin * 2
        let containerH = totalH + shadowMargin * 2

        let petCenterX = anchorWindowFrame.midX
        let petTopY = anchorWindowFrame.maxY
        var origin = NSPoint(
            x: petCenterX - totalW / 2 - shadowMargin,
            y: petTopY + 6 - shadowMargin
        )
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if origin.x + shadowMargin < screen.minX + 4 {
            origin.x = screen.minX + 4 - shadowMargin
        }
        if origin.x + shadowMargin + totalW > screen.maxX - 4 {
            origin.x = screen.maxX - 4 - totalW - shadowMargin
        }

        let win = NSWindow(
            contentRect: NSRect(origin: origin, size: NSSize(width: containerW, height: containerH)),
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

        let v = BubbleView(frame: NSRect(x: 0, y: 0, width: containerW, height: containerH))
        v.bubbleFrame = NSRect(x: shadowMargin, y: shadowMargin, width: totalW, height: totalH)
        v.bubbleHeight = layout.bubbleH
        v.tailHeight = layout.tailH
        let tailX = petCenterX - origin.x
        v.tailCenterX = max(shadowMargin + 22, min(shadowMargin + totalW - 22, tailX))
        v.anchorCenterX = petCenterX
        v.anchorTopY = petTopY
        win.contentView = v
        return win
    }
}

/// 排版结果。
@MainActor
private struct BubbleLayout {
    let bubbleH: CGFloat
    let tailH: CGFloat
    let totalW: CGFloat
    let totalH: CGFloat
    let shadowMargin: CGFloat

    static let font = NSFont.systemFont(ofSize: 13.5, weight: .regular)
    static let pad: CGFloat = 14
    static let maxWidth: CGFloat = 280
    static let minWidth: CGFloat = 96

    static func compute(text: String) -> BubbleLayout {
        let measured = text.isEmpty ? "正在想……" : text
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: para]
        let bounding = (measured as NSString).boundingRect(
            with: NSSize(width: maxWidth - pad * 2, height: 4000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        let textW = ceil(bounding.width)
        let textH = ceil(bounding.height)
        let bubbleW = max(minWidth, textW + pad * 2)
        let bubbleH = textH + pad * 2
        let tailH: CGFloat = 9
        return BubbleLayout(
            bubbleH: bubbleH,
            tailH: tailH,
            totalW: bubbleW,
            totalH: bubbleH + tailH,
            shadowMargin: 24
        )
    }
}

@MainActor
private final class BubbleView: NSView {
    var bubbleFrame: NSRect = .zero
    var bubbleHeight: CGFloat = 0
    var tailHeight: CGFloat = 0
    var tailCenterX: CGFloat = 0
    /// 锚点屏幕坐标(用于流式 relayout 保持气泡指向宠物中心)
    var anchorCenterX: CGFloat = 0
    var anchorTopY: CGFloat = 0

    private(set) var fullText: String = ""
    var currentTextCount: Int { fullText.count }
    var onClick: (() -> Void)?

    private let effectView = NSVisualEffectView()
    private let shadowLayer = CALayer()
    private let outlineLayer = CAShapeLayer()
    private let maskLayer = CAShapeLayer()
    private let textField = NSTextField(labelWithString: "")

    /// 流式增量
    func append(_ chunk: String) {
        fullText.append(chunk)
        updateText()
    }

    func replaceText(with text: String) {
        fullText = text
        updateText()
    }

    private func updateText() {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        let display = NSMutableAttributedString(
            string: fullText,
            attributes: [
                .font: BubbleLayout.font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: para
            ]
        )
        textField.attributedStringValue = display
        textField.needsDisplay = true
    }

    func setup() {
        wantsLayer = true
        layer?.masksToBounds = false

        shadowLayer.frame = bounds
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = 0.22
        shadowLayer.shadowOffset = CGSize(width: 0, height: -4)
        shadowLayer.shadowRadius = 14
        if shadowLayer.superlayer == nil { layer?.addSublayer(shadowLayer) }
        shadowLayer.shadowPath = bubblePath(inViewSpace: true).cgPathCompat

        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.frame = bubbleFrame
        maskLayer.frame = effectView.bounds
        maskLayer.path = bubblePath(inViewSpace: false).cgPathCompat
        effectView.layer?.mask = maskLayer
        if effectView.superview !== self { addSubview(effectView) }

        outlineLayer.frame = bubbleFrame
        outlineLayer.path = bubblePath(inViewSpace: false).cgPathCompat
        outlineLayer.fillColor = NSColor.clear.cgColor
        outlineLayer.strokeColor = NSColor(white: 1.0, alpha: 0.12).cgColor
        outlineLayer.lineWidth = 0.5
        outlineLayer.zPosition = 10
        if outlineLayer.superlayer == nil { layer?.addSublayer(outlineLayer) }

        textField.isBezeled = false
        textField.isEditable = false
        textField.isSelectable = false
        textField.drawsBackground = false
        textField.backgroundColor = .clear
        textField.lineBreakMode = .byWordWrapping
        textField.maximumNumberOfLines = 0
        textField.cell?.wraps = true
        textField.cell?.isScrollable = false
        textField.usesSingleLineMode = false
        if textField.superview !== self { addSubview(textField) }
        applyLayout()
    }

    /// 几何变更后重新铺一遍 frame + path,文字 frame 也更新。
    func applyLayout() {
        shadowLayer.frame = bounds
        shadowLayer.shadowPath = bubblePath(inViewSpace: true).cgPathCompat

        effectView.frame = bubbleFrame
        maskLayer.frame = effectView.bounds
        maskLayer.path = bubblePath(inViewSpace: false).cgPathCompat

        outlineLayer.frame = bubbleFrame
        outlineLayer.path = bubblePath(inViewSpace: false).cgPathCompat

        let pad = BubbleLayout.pad
        let textRect = NSRect(
            x: bubbleFrame.minX + pad,
            y: bubbleFrame.minY + tailHeight + pad,
            width: bubbleFrame.width - pad * 2,
            height: bubbleHeight - pad * 2
        )
        textField.frame = textRect
        updateText()
    }

    private func bubblePath(inViewSpace: Bool) -> NSBezierPath {
        let W = bubbleFrame.width
        let radius: CGFloat = 14
        let tailHalfWidth: CGFloat = 8

        let bubbleRect: NSRect
        let tailLeft: NSPoint
        let tailTip: NSPoint
        let tailRight: NSPoint
        if inViewSpace {
            bubbleRect = NSRect(
                x: bubbleFrame.minX,
                y: bubbleFrame.minY + tailHeight,
                width: W,
                height: bubbleHeight
            )
            tailLeft  = NSPoint(x: tailCenterX - tailHalfWidth, y: bubbleFrame.minY + tailHeight)
            tailRight = NSPoint(x: tailCenterX + tailHalfWidth, y: bubbleFrame.minY + tailHeight)
            tailTip   = NSPoint(x: tailCenterX,                 y: bubbleFrame.minY)
        } else {
            let cx = tailCenterX - bubbleFrame.minX
            bubbleRect = NSRect(x: 0, y: tailHeight, width: W, height: bubbleHeight)
            tailLeft  = NSPoint(x: cx - tailHalfWidth, y: tailHeight)
            tailRight = NSPoint(x: cx + tailHalfWidth, y: tailHeight)
            tailTip   = NSPoint(x: cx,                 y: 0)
        }
        let path = NSBezierPath(roundedRect: bubbleRect, xRadius: radius, yRadius: radius)
        let tail = NSBezierPath()
        tail.move(to: tailLeft)
        tail.curve(to: tailTip,
                   controlPoint1: NSPoint(x: tailLeft.x + 2, y: tailLeft.y - 2),
                   controlPoint2: NSPoint(x: tailTip.x - 2, y: tailTip.y + 1))
        tail.curve(to: tailRight,
                   controlPoint1: NSPoint(x: tailTip.x + 2, y: tailTip.y + 1),
                   controlPoint2: NSPoint(x: tailRight.x - 2, y: tailRight.y - 2))
        tail.close()
        path.append(tail)
        return path
    }

    override func mouseUp(with event: NSEvent) { onClick?() }
}

// MARK: - NSBezierPath -> CGPath 兼容(macOS 13)

private extension NSBezierPath {
    var cgPathCompat: CGPath {
        if #available(macOS 14.0, *) {
            return self.cgPath
        }
        let path = CGMutablePath()
        var pts = [CGPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &pts)
            switch type {
            case .moveTo:    path.move(to: pts[0])
            case .lineTo:    path.addLine(to: pts[0])
            case .curveTo:   path.addCurve(to: pts[2], control1: pts[0], control2: pts[1])
            case .cubicCurveTo:     path.addCurve(to: pts[2], control1: pts[0], control2: pts[1])
            case .quadraticCurveTo: path.addQuadCurve(to: pts[1], control: pts[0])
            case .closePath: path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }
}
