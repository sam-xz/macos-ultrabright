import Cocoa

private final class BrightnessHUDBackground: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16).fill()
    }
}

final class BrightnessHUD {
    private var window: NSWindow?
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private var dismissal: DispatchWorkItem?

    func show(percent: Double, nits: Double, screen: NSScreen) {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 90),
                styleMask: .borderless, backing: .buffered, defer: false)
            panel.level = .statusBar; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.hasShadow = true; panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            // Draw one shape. A HUD material on NSPanel adds its own frame on
            // macOS 27, leaving a rectangular backing outside rounded corners.
            let background = BrightnessHUDBackground(frame: panel.contentView!.bounds)
            title.frame = NSRect(x: 18, y: 53, width: 204, height: 23)
            title.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
            title.alignment = .center
            detail.frame = NSRect(x: 18, y: 30, width: 204, height: 19)
            detail.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            detail.alignment = .center; detail.textColor = .secondaryLabelColor
            progress.frame = NSRect(x: 20, y: 16, width: 200, height: 5)
            progress.isIndeterminate = false; progress.minValue = 0; progress.maxValue = 140
            background.addSubview(title); background.addSubview(detail); background.addSubview(progress)
            panel.contentView = background; window = panel
        }
        title.stringValue = "\(percent > 100 ? "XDR" : "SDR") · \(Int(percent.rounded()))%"
        title.textColor = percent > 100 ? .systemOrange : .labelColor
        detail.stringValue = "≈\(Int(nits.rounded())) nits"
        progress.doubleValue = percent
        window?.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 120, y: screen.visibleFrame.minY + 70))
        window?.orderFrontRegardless()
        window?.invalidateShadow()
        dismissal?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.window?.orderOut(nil) }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }
    func hide() { dismissal?.cancel(); dismissal = nil; window?.orderOut(nil) }
}

final class BrightnessSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = NSRect(x: rect.minX, y: rect.midY - 3, width: rect.width, height: 6)
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).fill()
        let boundary = track.minX + track.width * 100 / 140
        NSColor.systemOrange.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: NSRect(x: boundary, y: track.minY, width: track.maxX - boundary, height: track.height), xRadius: 3, yRadius: 3).fill()
        let filled = track.width * CGFloat(doubleValue / 140)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: min(filled, boundary - track.minX), height: track.height), xRadius: 3, yRadius: 3).fill()
        if doubleValue > 100 {
            NSColor.systemOrange.setFill()
            NSBezierPath(roundedRect: NSRect(x: boundary, y: track.minY, width: max(0, filled - (boundary - track.minX)), height: track.height), xRadius: 3, yRadius: 3).fill()
        }
        NSColor.secondaryLabelColor.setFill()
        NSRect(x: boundary - 0.5, y: track.minY - 3, width: 1, height: 12).fill()
    }
}

final class BrightnessSliderView: NSView {
    let slider = NSSlider(value: 0, minValue: 0, maxValue: 140, target: nil, action: nil)
    private let percentLabel = NSTextField(labelWithString: "")
    private let nitsLabel = NSTextField(labelWithString: "")
    private let modeLabel = NSTextField(labelWithString: "SDR")
    private let note = NSTextField(labelWithString: "Estimated luminance")

    init(target: AnyObject, action: Selector) {
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: 148))
        func label(_ text: String, _ frame: NSRect, size: CGFloat = 11, color: NSColor = .secondaryLabelColor) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.frame = frame
            field.font = .systemFont(ofSize: size)
            field.textColor = color
            addSubview(field)
            return field
        }
        _ = label("Brightness", NSRect(x: 18, y: 113, width: 130, height: 22), size: 14, color: .labelColor)
        percentLabel.frame = NSRect(x: 216, y: 110, width: 106, height: 29)
        percentLabel.font = .monospacedDigitSystemFont(ofSize: 23, weight: .semibold)
        percentLabel.alignment = .right
        addSubview(percentLabel)
        modeLabel.frame = NSRect(x: 18, y: 91, width: 100, height: 18)
        modeLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        addSubview(modeLabel)
        nitsLabel.frame = NSRect(x: 150, y: 88, width: 172, height: 21)
        nitsLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        nitsLabel.alignment = .right
        nitsLabel.textColor = .secondaryLabelColor
        addSubview(nitsLabel)
        slider.cell = BrightnessSliderCell()
        slider.minValue = 0; slider.maxValue = 140
        slider.frame = NSRect(x: 18, y: 56, width: 304, height: 24)
        slider.isContinuous = true
        slider.target = target; slider.action = action
        slider.setAccessibilityLabel("Total display brightness")
        addSubview(slider)
        _ = label("0%", NSRect(x: 20, y: 34, width: 36, height: 17))
        _ = label("100% SDR", NSRect(x: 195, y: 34, width: 78, height: 17))
        let maximum = label("140%", NSRect(x: 277, y: 34, width: 44, height: 17), color: .systemOrange)
        maximum.alignment = .right
        note.frame = NSRect(x: 18, y: 9, width: 304, height: 18)
        note.font = .systemFont(ofSize: 10)
        note.textColor = .tertiaryLabelColor
        addSubview(note)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(percent: Double, nits: Double, message: String? = nil) {
        slider.doubleValue = percent
        slider.needsDisplay = true
        percentLabel.stringValue = "\(Int(percent.rounded()))%"
        nitsLabel.stringValue = "≈\(Int(nits.rounded())) nits"
        modeLabel.stringValue = percent > 100 ? "XDR" : "SDR"
        modeLabel.textColor = percent > 100 ? .systemOrange : .secondaryLabelColor
        note.stringValue = message ?? "Estimated luminance"
        note.textColor = message == nil ? .tertiaryLabelColor : .systemRed
        slider.setAccessibilityValueDescription("\(Int(percent.rounded())) percent, approximately \(Int(nits.rounded())) nits, \(modeLabel.stringValue)")
    }
}
