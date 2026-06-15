import Foundation

/// Pure helpers for converting audio sample representations.
///
/// These functions are pure, allocation-light, and safe to call from the
/// audio render thread. The conversions follow the standard
/// `Int16 / 32_768 = Float` mapping used by every major STT engine
/// (Whisper, Grok, etc.).
public enum AudioSampleConverter {

    /// Convert 16-bit signed integer samples in `[-32_768, 32_767]` to
    /// `Float` samples in `[-1.0, 1.0]`.
    public static func float(from samples: [Int16]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        var out = [Float]()
        out.reserveCapacity(samples.count)
        for s in samples {
            out.append(Float(s) / 32_768.0)
        }
        return out
    }

    /// Convert `Float` samples to 16-bit signed integers, clamping to the
    /// representable range `[-32_768, 32_767]`.
    public static func int16(from samples: [Float]) -> [Int16] {
        guard !samples.isEmpty else { return [] }
        var out = [Int16]()
        out.reserveCapacity(samples.count)
        for s in samples {
            let clamped = Swift.max(-1.0, Swift.min(1.0, s))
            // Round to nearest to keep the round-trip symmetric within 1 LSB.
            out.append(Int16((clamped * 32_768.0).rounded()))
        }
        return out
    }
}
