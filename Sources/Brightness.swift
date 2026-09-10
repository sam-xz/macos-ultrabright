import Cocoa
import Darwin

struct BrightnessProfile {
    let sdrNits: Double
    let maximumNits: Double
    let maximumHeadroom: Double
    let nativeSteps: [Double]
    static let maximumPercent = 140.0
    static let maximumGain = 1.6
    // An estimate of panel response, used only to choose a scalar gain.
    // The captured RGB curves themselves are never exponentiated or clipped.
    static let estimatedResponse = 2.2

    init?(sdrNits: Double, hdrNits: Double, nativeSteps: [Double]) {
        guard sdrNits.isFinite, hdrNits.isFinite, sdrNits > 0, hdrNits > sdrNits,
              nativeSteps.count > 1, nativeSteps.allSatisfy({ $0.isFinite && $0 >= 0 }),
              zip(nativeSteps, nativeSteps.dropFirst()).allSatisfy({ $0 <= $1 }),
              abs(nativeSteps.last! - sdrNits) < 1,
              min(1400, hdrNits) > sdrNits else { return nil }
        self.sdrNits = sdrNits
        self.maximumNits = min(1400, hdrNits, sdrNits * pow(Self.maximumGain, Self.estimatedResponse))
        self.maximumHeadroom = hdrNits / sdrNits
        self.nativeSteps = nativeSteps
    }

    func nits(at percent: Double) -> Double {
        let p = min(max(percent, 0), Self.maximumPercent)
        if p > 100 { return sdrNits + (maximumNits - sdrNits) * (p - 100) / 40 }
        let index = p / 100 * Double(nativeSteps.count - 1)
        let lower = min(Int(index), nativeSteps.count - 2)
        return nativeSteps[lower] + (nativeSteps[lower + 1] - nativeSteps[lower]) * (index - Double(lower))
    }

    func gain(at percent: Double) -> Float {
        guard percent > 100 else { return 1 }
        return Float(min(Self.maximumGain, pow(nits(at: percent) / sdrNits, 1 / Self.estimatedResponse)))
    }

    static func load(display: CGDirectDisplayID) -> BrightnessProfile? {
        // CoreBrightness supplies the built-in panel's calibrated native steps.
        // Read once at launch; no model-name guesses or fabricated nits values.
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/libexec/corebrightnessdiag")
        process.arguments = ["status-info"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if process.isRunning { process.terminate() }
        }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: output, encoding: .utf8),
              let start = text.range(of: "<?xml"), let end = text.range(of: "</plist>"),
              start.lowerBound < end.upperBound,
              let data = String(text[start.lowerBound..<end.upperBound]).data(using: .utf8),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let displays = root["CBDisplays"] as? [String: [String: Any]],
              let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() else { return nil }
        let key = CFUUIDCreateString(nil, uuid) as String
        guard let entry = displays.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value,
              let caps = entry["BrightnessControlCapabilities"] as? [String: Any],
              let sdr = caps["MaxNits"] as? Double, let hdr = caps["MaxNitsEDR"] as? Double,
              let steps = caps["NitsToUserBrightnessTable"] as? [Double] else { return nil }
        return BrightnessProfile(sdrNits: sdr, hdrNits: hdr, nativeSteps: steps)
    }
}

final class HardwareBrightness {
    typealias Read = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    typealias Write = @convention(c) (UInt32, Float) -> Int32
    private let handle: UnsafeMutableRawPointer
    private let get: Read
    private let getLinear: Read
    private let set: Write
    let display: CGDirectDisplayID

    init?(display: CGDirectDisplayID) {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else { return nil }
        guard let read = dlsym(handle, "DisplayServicesGetBrightness"),
              let linear = dlsym(handle, "DisplayServicesGetLinearBrightness"),
              let write = dlsym(handle, "DisplayServicesSetBrightness") else { dlclose(handle); return nil }
        self.handle = handle
        self.display = display
        get = unsafeBitCast(read, to: Read.self)
        getLinear = unsafeBitCast(linear, to: Read.self)
        set = unsafeBitCast(write, to: Write.self)
    }
    deinit { dlclose(handle) }
    func read() -> Double? {
        var value: Float = 0
        guard get(display, &value) == 0, value.isFinite, (0...1).contains(value) else { return nil }
        return Double(value)
    }
    func linear() -> Double? {
        var value: Float = 0
        guard getLinear(display, &value) == 0, value.isFinite, value >= 0 else { return nil }
        return Double(value)
    }
    @discardableResult func write(_ value: Double) -> Bool {
        guard value.isFinite, (0...1).contains(value) else { return false }
        return set(display, Float(value)) == 0
    }
}
