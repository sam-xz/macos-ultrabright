import Cocoa
import QuartzCore

enum BrightnessTransition {
    static let gainTolerance: Float = 0.00005

    static func nextGain(from current: Float, to target: Float, elapsed: Double) -> Float {
        // Bound each frame even if the main run loop was briefly delayed.
        let dt = min(max(elapsed, 0), 1.0 / 30)
        let difference = target - current
        let eased = difference * Float(1 - exp(-dt / 0.035))
        let maximumChange = Float(0.8 * dt)
        let next = current + min(max(eased, -maximumChange), maximumChange)
        return abs(next - target) <= gainTolerance ? target : next
    }
}

final class DisplayFrameClock: NSObject {
    private var callback: (() -> Void)?
    private var invalidate: (() -> Void)?
    var isRunning: Bool { invalidate != nil }

    func start(screen: NSScreen, callback: @escaping () -> Void) {
        stop()
        self.callback = callback
        if #available(macOS 14.0, *) {
            let link = screen.displayLink(target: self, selector: #selector(frame))
            let rate = Float(min(120, screen.maximumFramesPerSecond))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, rate), maximum: rate, preferred: rate)
            invalidate = { link.invalidate() }
            link.add(to: .main, forMode: .common)
        } else {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.callback?() }
            invalidate = { timer.invalidate() }
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    @objc private func frame() { callback?() }
    func stop() { invalidate?(); invalidate = nil; callback = nil }
    deinit { stop() }
}
