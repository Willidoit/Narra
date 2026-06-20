import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Snapshot of the machine's relevant capabilities for picking a sane
/// default local model. Reads RAM via `ProcessInfo` and the CPU brand
/// via sysctl; both are cheap and stable for the app's lifetime.
public struct HardwareProfile: Sendable {
    public let physicalMemoryGB: Int
    public let cpuBrand: String
    public let isAppleSilicon: Bool

    public static let current: HardwareProfile = {
        let mem = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
        let brand = sysctlString(name: "machdep.cpu.brand_string") ?? ""
        let isApple = brand.contains("Apple")
        return HardwareProfile(
            physicalMemoryGB: mem,
            cpuBrand: brand,
            isAppleSilicon: isApple
        )
    }()

    /// Recommended model ID for a given local provider. The selection rule
    /// is intentionally simple — label-only, no hard gate. The user can
    /// still pick any model.
    public func recommendedModelID(for providerID: ProviderID) -> String? {
        switch providerID {
        case .whisperKit:
            switch physicalMemoryGB {
            case ..<8:    return "base"
            case 8..<16:  return "small"
            case 16..<32: return "medium"
            default:      return "large-v3"
            }
        case .appleSpeech:
            return "en-US"
        case .parakeet:
            return "parakeet-tdt-0.6b"
        case .groq, .openAI, .deepgram, .elevenLabs:
            return nil
        }
    }

    /// Short user-facing label: "16 GB · Apple M3 Pro".
    public var summary: String {
        let chip = isAppleSilicon ? cpuBrand : "Intel"
        return "\(physicalMemoryGB) GB · \(chip)"
    }
}

private func sysctlString(name: String) -> String? {
    var size: Int = 0
    sysctlbyname(name, nil, &size, nil, 0)
    guard size > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    sysctlbyname(name, &buffer, &size, nil, 0)
    return String(cString: buffer)
}
