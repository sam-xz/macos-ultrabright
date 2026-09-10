import Cocoa
import MetalKit
import Carbon.HIToolbox

final class Renderer: NSObject, MTKViewDelegate {
    let queue: MTLCommandQueue
    private(set) var hasPresented = false
    init(device: MTLDevice) { queue = device.makeCommandQueue()! }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor, let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        if let drawable = view.currentDrawable {
            if !hasPresented {
                drawable.addPresentedHandler { [weak self] _ in
                    DispatchQueue.main.async { self?.hasPresented = true }
                }
            }
            buffer.present(drawable)
        }
        buffer.commit()
    }
}

final class UltrabrightApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var panel: BrightnessSliderView!
    var toggleItem: NSMenuItem!
    var keysItem: NSMenuItem!
    let brightnessKeys = BrightnessKeys()
    let brightnessHUD = BrightnessHUD()
    var queuedKeyPercent: Double?
    var keyGeneration = 0
    var nextKeyAccessCheck = Date.distantPast
    var hardware: HardwareBrightness!
    var profile: BrightnessProfile!
    var device: MTLDevice!
    var percent = 0.0
    var lastXDRPercent = 110.0
    var gamma: GammaSession?
    let gammaFrames = DisplayFrameClock()
    var appliedGain: Float = 1
    var targetGain: Float = 1
    var lastGammaFrame = 0.0
    var triggerStartedAt: Double?
    var initialHeadroom = 1.0
    var warmupProgress = 0.0
    var previousSDRBrightness: Double?
    var pendingSDRPercent: Double?
    var window: NSWindow?
    var renderer: Renderer?
    var retryRestore = false
    var restoreHardware = true
    var wantsQuit = false
    var message: String?
    var lastWrite = Date.distantPast
    var timer: Timer?
    var signalSources: [DispatchSourceSignal] = []
    var hotkey: EventHotKeyRef?
    var wakePercent: Double?
    var displayAsleep = false
    var wakeReadyAt = Date.distantPast

    func id(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
    var screen: NSScreen? { NSScreen.screens.first { id($0) == hardware?.display } }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let builtIn = NSScreen.screens.first(where: { CGDisplayIsBuiltin(id($0)) != 0 }),
              let hardware = HardwareBrightness(display: id(builtIn)), let current = hardware.read(),
              let profile = BrightnessProfile.load(display: id(builtIn)),
              let device = MTLCreateSystemDefaultDevice() else {
            fputs("Could not read the built-in display's brightness calibration.\n", stderr)
            let alert = NSAlert()
            alert.messageText = "Display unavailable"
            alert.informativeText = "MacOS Ultrabright could not read the built-in display's brightness controls. This app needs a Liquid Retina XDR display."
            alert.addButton(withTitle: "Quit")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            NSApp.terminate(nil); return
        }
        self.hardware = hardware; self.profile = profile; self.device = device
        percent = current * 100
        setupMenu()
        registerHotkey()
        brightnessKeys.onPress = { [weak self] up, fine in self?.brightnessKey(up: up, fine: fine) ?? false }
        _ = brightnessKeys.start()
        if CommandLine.arguments.contains("--request-key-access") { enableBrightnessKeys() }
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in self?.quit() }
            source.resume(); signalSources.append(source)
        }
        timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer!, forMode: .common)
        NotificationCenter.default.addObserver(self, selector: #selector(displayChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleepDisplay), name: NSWorkspace.screensDidSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wakeDisplay), name: NSWorkspace.screensDidWakeNotification, object: nil)
        updateUI()
        fputs("MacOS Ultrabright ready: \(Int(percent.rounded()))%, SDR ceiling \(Int(profile.sdrNits)) nits, XDR target \(Int(profile.maximumNits)) nits. Starts without changing brightness.\n", stderr)
        fputs("Brightness keys: \(brightnessKeys.isActive ? "enabled" : "Accessibility access required").\n", stderr)
    }

    func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "MacOS Ultrabright brightness")
        let menu = NSMenu(); menu.delegate = self
        let item = NSMenuItem()
        panel = BrightnessSliderView(target: self, action: #selector(sliderChanged(_:)))
        item.view = panel; menu.addItem(item)
        menu.addItem(.separator())
        toggleItem = NSMenuItem(title: "Enable XDR", action: #selector(toggleXDR), keyEquivalent: "")
        toggleItem.target = self; menu.addItem(toggleItem)
        keysItem = NSMenuItem(title: "Enable brightness keys…", action: #selector(enableBrightnessKeys), keyEquivalent: "")
        keysItem.target = self; menu.addItem(keysItem)
        let shortcut = NSMenuItem(title: "Shortcut: Ctrl+Option+Cmd+V", action: nil, keyEquivalent: "")
        shortcut.isEnabled = false; menu.addItem(shortcut)
        menu.addItem(.separator())
        let about = NSMenuItem(title: "About MacOS Ultrabright", action: #selector(showAbout), keyEquivalent: "")
        about.target = self; menu.addItem(about)
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self; menu.addItem(quitItem)
        statusItem.menu = menu
    }
    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Forked from xdr-boost by Pieter Levels.\nReleased under the MIT licence.")
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
    func menuWillOpen(_ menu: NSMenu) { refresh() }
    func updateUI() {
        guard panel != nil else { return }
        let estimated = gamma == nil ? hardware.linear().map { $0 * profile.sdrNits } ?? profile.nits(at: percent) : profile.nits(at: percent)
        panel.update(percent: percent, nits: estimated, message: message)
        toggleItem.title = retryRestore ? "Retry Display Restoration" : gamma == nil ? "Enable XDR" : "Return to SDR"
        keysItem.title = brightnessKeys.isActive ? "Brightness keys enabled" : "Enable brightness keys…"
        keysItem.action = brightnessKeys.isActive ? nil : #selector(enableBrightnessKeys)
        keysItem.isEnabled = !brightnessKeys.isActive
        statusItem.button?.toolTip = "MacOS Ultrabright · \(Int(percent.rounded()))% · ≈\(Int(estimated.rounded())) nits"
    }
    @objc func sliderChanged(_ sender: NSSlider) {
        cancelQueuedKeys()
        wakePercent = nil
        setBrightness(sender.doubleValue.rounded())
    }
    @objc func toggleXDR() {
        cancelQueuedKeys()
        wakePercent = nil
        if retryRestore { _ = releaseBoost(restoreNative: restoreHardware); updateUI(); return }
        if gamma != nil { setBrightness(100) } else { setBrightness(lastXDRPercent) }
    }

    @objc func enableBrightnessKeys() {
        if !brightnessKeys.start() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        updateUI()
    }

    func cancelQueuedKeys() {
        keyGeneration += 1; queuedKeyPercent = nil
        brightnessHUD.hide()
    }

    // Decide in the event callback; perform display writes after it returns.
    func brightnessKey(up: Bool, fine: Bool) -> Bool {
        guard !wantsQuit, !displayAsleep, screen != nil else { return false }
        wakePercent = nil
        guard let native = hardware.read() else { return false }
        let step = fine ? 1.5625 : 6.25
        if retryRestore {
            // Keep newer key input in the pending native target. A retry must
            // not overwrite it or re-enable XDR before restoration succeeds.
            let current = pendingSDRPercent
                ?? (restoreHardware ? previousSDRBrightness.map { $0 * 100 } : nil)
                ?? native * 100
            pendingSDRPercent = min(100, max(0, current + (up ? step : -step)))
            return true
        }
        let current = queuedKeyPercent ?? (gamma == nil ? native * 100 : percent)
        guard queuedKeyPercent != nil || gamma != nil || (up && native >= 0.999) else { return false }
        var target = min(140, max(0, current + (up ? step : -step)))
        // Stop on the SDR boundary before continuing down into native brightness.
        if current > 100, target < 100 { target = 100 }
        queuedKeyPercent = target; keyGeneration += 1
        let generation = keyGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == self.keyGeneration else { return }
            self.queuedKeyPercent = nil
            guard !self.wantsQuit, !self.displayAsleep, !self.retryRestore else { return }
            if self.setBrightness(target), let screen = self.screen {
                self.brightnessHUD.show(percent: self.percent, nits: self.profile.nits(at: self.percent), screen: screen)
            }
        }
        return true
    }

    @discardableResult func setBrightness(_ value: Double) -> Bool {
        guard value.isFinite, (0...140).contains(value), !retryRestore else { return false }
        message = nil
        lastWrite = Date()
        if value <= 100 {
            pendingSDRPercent = value
            if gamma != nil, appliedGain > 1 {
                animateGamma(to: 1)
            } else {
                guard releaseBoost(restoreNative: false) else { updateUI(); return false }
            }
            percent = value
        } else {
            guard let screen = screen, screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1 else {
                fail("XDR is unavailable on this display"); return false
            }
            if gamma == nil {
                guard let before = hardware.read(), let session = GammaSession(display: hardware.display) else {
                    fail("Quit other brightness utilities first"); return false
                }
                gamma = session; previousSDRBrightness = before
                guard hardware.write(1) else {
                    _ = releaseBoost(restoreNative: true); fail("Could not set SDR brightness"); return false
                }
                createTrigger(screen)
            }
            pendingSDRPercent = nil
            animateGamma(to: profile.gain(at: value))
            percent = value; lastXDRPercent = value
        }
        updateUI()
        return true
    }
    func fail(_ text: String) {
        message = text; fputs("\(text)\n", stderr)
        if gamma == nil, let current = hardware.read() { percent = current * 100 }
        updateUI()
    }

    func animateGamma(to gain: Float) {
        targetGain = gain
        guard !gammaFrames.isRunning, let screen else { return }
        lastGammaFrame = CACurrentMediaTime()
        gammaFrames.start(screen: screen) { [weak self] in self?.advanceGamma() }
    }

    func advanceGamma() {
        guard let gamma, let screen, !displayAsleep, !wantsQuit, !retryRestore else {
            gammaFrames.stop(); return
        }
        let now = CACurrentMediaTime()
        let elapsed = now - lastGammaFrame
        lastGammaFrame = now
        // A native edit during the fade takes precedence over its queued target.
        if let native = hardware.read(), native < 0.999 {
            pendingSDRPercent = nil; cancelQueuedKeys()
            _ = releaseBoost(restoreNative: false); updateUI(); return
        }
        var availableTarget = targetGain
        if targetGain > 1, let started = triggerStartedAt {
            let headroom = Double(screen.maximumExtendedDynamicRangeColorComponentValue)
            let span = profile.maximumHeadroom - initialHeadroom
            if renderer?.hasPresented == true {
                if span <= 0.002 {
                    warmupProgress = 1
                } else {
                    warmupProgress = max(warmupProgress, min(1, max(0, (headroom - initialHeadroom) / span)))
                }
            }
            if warmupProgress >= 0.998 {
                triggerStartedAt = nil
            } else if now - started > 1.5 {
                // Do not apply the full curve while the display cannot sustain it.
                let requiredHeadroom = profile.nits(at: percent) / profile.sdrNits
                if renderer?.hasPresented == true, headroom >= requiredHeadroom, warmupProgress > 0 {
                    triggerStartedAt = nil; warmupProgress = 1
                } else {
                    cancelQueuedKeys()
                    _ = releaseBoost(restoreNative: true)
                    fail("XDR brightness is unavailable at present"); return
                }
            }
            availableTarget = 1 + (targetGain - 1) * Float(warmupProgress)
        }
        let next = BrightnessTransition.nextGain(from: appliedGain, to: availableTarget, elapsed: elapsed)
        if next != appliedGain {
            guard gamma.apply(gain: next) else {
                cancelQueuedKeys()
                _ = releaseBoost(restoreNative: true); fail("Could not update XDR brightness"); return
            }
            appliedGain = next; lastWrite = Date()
        }
        if appliedGain == targetGain {
            gammaFrames.stop()
            if targetGain == 1, pendingSDRPercent != nil {
                _ = releaseBoost(restoreNative: false); updateUI()
            }
        }
    }

    func createTrigger(_ screen: NSScreen) {
        triggerStartedAt = CACurrentMediaTime()
        initialHeadroom = Double(screen.maximumExtendedDynamicRangeColorComponentValue)
        warmupProgress = 0
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: 8, height: 8)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver; window.backgroundColor = .clear; window.isOpaque = false
        window.hasShadow = false; window.ignoresMouseEvents = true; window.hidesOnDeactivate = false
        window.sharingType = .none
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let view = MTKView(frame: NSRect(origin: .zero, size: frame.size), device: device)
        view.colorPixelFormat = .rgba16Float
        view.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        view.preferredFramesPerSecond = 10
        let white = Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue)
        view.clearColor = MTLClearColor(red: white, green: white, blue: white, alpha: 1)
        (view.layer as? CAMetalLayer)?.wantsExtendedDynamicRangeContent = true
        renderer = Renderer(device: device); view.delegate = renderer
        window.contentView = view; window.orderFrontRegardless(); self.window = window
        // Submit the first frame now instead of waiting for the 10 Hz keep-alive.
        view.draw()
    }

    @discardableResult func releaseBoost(restoreNative: Bool) -> Bool {
        gammaFrames.stop(); triggerStartedAt = nil
        restoreHardware = restoreNative
        guard gamma?.restore() != false else {
            retryRestore = true; message = "Restoring display…"; return false
        }
        appliedGain = 1; targetGain = 1
        window?.orderOut(nil); window = nil; renderer = nil
        let nativeTarget = pendingSDRPercent.map { $0 / 100 } ?? (restoreNative ? previousSDRBrightness : nil)
        if let target = nativeTarget, !hardware.write(target) {
            retryRestore = true; message = "Restoring display…"; return false
        }
        pendingSDRPercent = nil
        gamma = nil; previousSDRBrightness = nil; retryRestore = false; message = nil
        if let current = hardware?.read() { percent = current * 100 }
        return true
    }
    func refresh() {
        guard hardware != nil else { return }
        if !wantsQuit, !displayAsleep, Date() >= nextKeyAccessCheck {
            nextKeyAccessCheck = Date().addingTimeInterval(3)
            if !brightnessKeys.isActive, AXIsProcessTrusted(), brightnessKeys.start() {
                fputs("Brightness keys enabled.\n", stderr)
            }
        }
        if retryRestore {
            if releaseBoost(restoreNative: restoreHardware), wantsQuit { quit(); return }
        } else if let current = hardware.read(), Date().timeIntervalSince(lastWrite) > 0.5 {
            // Respect native edits made in System Settings or without key access.
            if gamma != nil, current < 0.999 {
                cancelQueuedKeys(); _ = releaseBoost(restoreNative: false)
            }
            if gamma == nil { percent = current * 100 }
        }
        resumeAfterWakeIfReady()
        updateUI()
    }
    @objc func displayChanged() {
        guard let screen = screen else {
            cancelQueuedKeys()
            if gamma != nil { _ = releaseBoost(restoreNative: true) }
            updateUI(); return
        }
        // Headroom notifications do not rebuild the small trigger.
        if let window = window {
            let origin = NSPoint(x: screen.frame.minX, y: screen.frame.minY)
            if window.frame.origin != origin { window.setFrameOrigin(origin) }
        }
    }
    @objc func sleepDisplay() {
        cancelQueuedKeys(); brightnessKeys.resetHeldKeys()
        displayAsleep = true
        if gamma != nil, !retryRestore {
            wakePercent = percent
            _ = releaseBoost(restoreNative: true)
        }
    }
    @objc func wakeDisplay() {
        displayAsleep = false
        wakeReadyAt = Date().addingTimeInterval(1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.resumeAfterWakeIfReady()
        }
    }
    func resumeAfterWakeIfReady() {
        guard !wantsQuit, !displayAsleep, !retryRestore, Date() >= wakeReadyAt,
              let resume = wakePercent else { return }
        if setBrightness(resume) || !retryRestore { wakePercent = nil }
    }

    func registerHotkey() {
        let identifier = EventHotKeyID(signature: OSType(0x554C4252), id: 1)
        guard RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(controlKey | optionKey | cmdKey), identifier, GetApplicationEventTarget(), 0, &hotkey) == noErr else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, pointer in
            guard let pointer = pointer else { return noErr }
            let app = Unmanaged<UltrabrightApp>.fromOpaque(pointer).takeUnretainedValue()
            DispatchQueue.main.async { app.toggleXDR() }; return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), nil)
    }
    @objc func quit() {
        if prepareToTerminate() { NSApp.terminate(nil) }
    }
    func prepareToTerminate() -> Bool {
        cancelQueuedKeys()
        wantsQuit = true; wakePercent = nil
        guard releaseBoost(restoreNative: true) else { updateUI(); return false }
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        prepareToTerminate() ? .terminateNow : .terminateCancel
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate(); brightnessKeys.stop()
    }

}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = UltrabrightApp()
app.delegate = delegate
app.run()
