import Cocoa

// Only the display brightness keys are handled. Other input passes unchanged.
final class BrightnessKeys {
    var onPress: ((Bool, Bool) -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var passedDown = Set<Int>()
    private var consumedDown = Set<Int>()

    var isActive: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    @discardableResult func start() -> Bool {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
            return isActive
        }
        let mask: CGEventMask = (1 << NSEvent.EventType.systemDefined.rawValue)
            | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, pointer in
                guard let pointer else { return Unmanaged.passUnretained(event) }
                let keys = Unmanaged<BrightnessKeys>.fromOpaque(pointer).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    keys.resetHeldKeys()
                    if let tap = keys.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                return keys.handle(event) ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
            let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else { return false }
        self.tap = tap; self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return isActive
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil; tap = nil; resetHeldKeys()
    }
    deinit { stop() }
    func resetHeldKeys() { passedDown.removeAll(); consumedDown.removeAll() }

    func handle(_ event: CGEvent) -> Bool {
        guard let native = NSEvent(cgEvent: event) else { return false }
        let key: Int
        let down: Bool
        let repeatPress: Bool
        if native.type == .systemDefined, native.subtype.rawValue == 8 {
            key = (native.data1 >> 16) & 0xffff
            guard key == 2 || key == 3 else { return false }
            let state = (native.data1 >> 8) & 0xff
            guard state == 0x0a || state == 0x0b else { return false }
            down = state == 0x0a
            repeatPress = (native.data1 & 1) != 0
        } else if native.type == .keyDown || native.type == .keyUp {
            // Some Apple keyboards send brightness as dedicated function events.
            guard native.keyCode == 144 || native.keyCode == 145 else { return false }
            key = native.keyCode == 144 ? 2 : 3
            down = native.type == .keyDown
            repeatPress = down && native.isARepeat
        } else { return false }

        if !down {
            let consumed = consumedDown.remove(key) != nil
            let passed = passedDown.remove(key) != nil
            // macOS must receive an up if it received any part of this press.
            return consumed && !passed
        }
        if !repeatPress { passedDown.remove(key); consumedDown.remove(key) }
        let modifiers = native.modifierFlags.intersection([.shift, .option, .control, .command])
        let fine = modifiers == [.shift, .option]
        // Keep Option+brightness (Displays settings) and other shortcuts intact.
        guard modifiers.isEmpty || modifiers == .shift || fine else {
            passedDown.insert(key); return false
        }
        let consumed = onPress?(key == 2, fine) ?? false
        if consumed { consumedDown.insert(key) } else { passedDown.insert(key) }
        return consumed
    }
}
