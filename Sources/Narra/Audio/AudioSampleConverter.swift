import Foundation

/// Pure helpers for converting audio sample representations.
///
/// These functions are pure, allocation-light, and safe to call from the
/// audio render thread. The conversions follow the standard
/// `Int16 / 32_768 = Float` mapping used by every major STT engine
/// (Whisper, Grok, etc.).
public enum AudioSampleConverter {

    /// Convert 16-bit signed integer samples in `[-32_768, 32_767]` to
    /// `Float` samples in `[-1.0, 1.0]`. Int16's range is asymmetric so we
    /// special-case `Int16.min` (no positive counterpart of 32_768) and
    /// scale the rest by `Int16.max` — that way `Int16.max` lands exactly
    /// on `1.0` and the round-trip with `int16(from:)` is closed.
    public static func float(from samples: [Int16]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        var out = [Float]()
        out.reserveCapacity(samples.count)
        let denom = Float(Int16.max)
        for s in samples {
            if s == Int16.min {
                out.append(-1.0)
            } else {
                out.append(Float(s) / denom)
            }
        }
        return out
    }

    /// Convert `Float` samples to 16-bit signed integers, clamping to the
    /// representable range `[-32_768, 32_767]`. `-1.0` maps to `Int16.min`
    /// as a deliberate edge case; everything else scales by `Int16.max`.
    public static func int16(from samples: [Float]) -> [Int16] {
        guard !samples.isEmpty else { return [] }
        var out = [Int16]()
        out.reserveCapacity(samples.count)
        let scale = Float(Int16.max)
        for s in samples {
            let clamped = Swift.max(-1.0, Swift.min(1.0, s))
            if clamped <= -1.0 {
                out.append(.min)
            } else {
                out.append(Int16((clamped * scale).rounded()))
            }
        }
        return out
    }
}
