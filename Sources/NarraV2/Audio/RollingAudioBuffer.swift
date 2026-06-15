import Foundation
import os.lock

/// A thread-safe, fixed-capacity ring of mono Int16 audio samples.
///
/// `RollingAudioBuffer` keeps the most recent N seconds of audio so the
/// application can:
///
/// - **Flush** the entire current contents (e.g. on stop) and hand them
///   to the transcription service as a single chunk.
/// - **Query a sliding window** of the most recent K seconds (e.g. to send
///   the last 5 seconds to a streaming STT endpoint).
///
/// The buffer is internally serialized with an `os_unfair_lock`, making
/// `append`, `last(seconds:)`, `flush`, and `clear` safe to call from any
/// thread — including the real-time audio render thread.
public final class RollingAudioBuffer: @unchecked Sendable {

    // MARK: - Configuration

    public let capacitySeconds: Double
    public let sampleRate: Double

    /// Maximum number of samples the buffer can hold. Computed from
    /// `capacitySeconds * sampleRate`. Zero or negative inputs yield zero
    /// capacity and the buffer will reject all samples.
    public var capacity: Int {
        let raw = Int((capacitySeconds * sampleRate).rounded())
        return max(0, raw)
    }

    // MARK: - State

    private var storage: [Int16]
    private var lock = os_unfair_lock_s()

    // MARK: - Init

    public init(capacitySeconds: Double, sampleRate: Double) {
        self.capacitySeconds = capacitySeconds
        self.sampleRate = sampleRate
        self.storage = []
        self.storage.reserveCapacity(min(Int(capacitySeconds * sampleRate), 1_048_576))
    }

    // MARK: - Mutating API

    /// Append samples to the buffer. If the new total would exceed the
    /// capacity, the oldest samples are dropped.
    public func append(_ samples: [Int16]) {
        guard !samples.isEmpty, capacity > 0 else { return }

        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        // If the incoming batch alone exceeds capacity, keep only its tail.
        if samples.count >= capacity {
            storage = Array(samples.suffix(capacity))
            return
        }

        storage.append(contentsOf: samples)
        let overflow = storage.count - capacity
        if overflow > 0 {
            storage.removeFirst(overflow)
        }
    }

    /// Return the most recent `seconds` of audio. Returns `[]` when:
    /// - `seconds <= 0`
    /// - the buffer is empty
    /// - fewer samples are available than requested (all available samples
    ///   are returned in that case)
    public func last(seconds: Double) -> [Int16] {
        guard seconds > 0, sampleRate > 0 else { return [] }

        let count = min(Int((seconds * sampleRate).rounded()), capacity)
        guard count > 0 else { return [] }

        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        if storage.count <= count {
            return storage
        }
        return Array(storage.suffix(count))
    }

    /// Return all samples currently in the buffer, then clear it.
    public func flush() -> [Int16] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        let snapshot = storage
        storage.removeAll(keepingCapacity: true)
        return snapshot
    }

    /// Discard all buffered samples.
    public func clear() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        storage.removeAll(keepingCapacity: true)
    }

    // MARK: - Read-only

    public var sampleCount: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return storage.count
    }

    public var duration: Double {
        guard sampleRate > 0 else { return 0 }
        return Double(sampleCount) / sampleRate
    }
}
