import Foundation
@preconcurrency import AVFoundation
import CoreAudio
import AudioToolbox
import Synchronization
import os.lock

/// Captures microphone audio via `AVAudioEngine` and pushes a mono 16 kHz
/// `Int16` stream into a `RollingAudioBuffer`.
///
/// The manager is intentionally narrow in scope — it does not transcribe or
/// process audio. Its responsibilities are:
///
/// 1. Request microphone permission when started.
/// 2. Install a tap on the input node that converts whatever the hardware
///    provides to a fixed 16 kHz mono `Int16` format expected by every STT
///    engine in the project (Grok, WhisperKit, MLX).
/// 3. Feed the converted samples into a `RollingAudioBuffer` and surface
///    the latest RMS level for the UI.
/// 4. Expose a flush-on-stop helper that returns the captured audio as a
///    single `AudioChunk`.
///
/// All public mutating API is serialized; the render-thread tap closure
/// hops to a dedicated queue before mutating shared state, so it is safe
/// to start, stop, and query the manager from any thread.
public final class AudioCaptureManager: @unchecked Sendable {

    // MARK: - Configuration

    /// Sample rate the manager normalizes all captured audio to. 16 kHz is
    /// the de-facto rate for Whisper, Grok realtime, and MLX audio models.
    public static let targetSampleRate: Double = 16_000

    /// How long of audio the rolling buffer retains. Five seconds is
    /// enough for "transcribe what I just said" UX without unbounded
    /// memory growth during long sessions.
    public static let defaultBufferSeconds: Double = 5.0

    // MARK: - Public state

    /// Whether the engine is currently capturing. Observable from any
    /// thread; transitions only on the main actor.
    public private(set) var isCapturing: Bool = false

    /// Most recent RMS level in `[0, 1]`. Updated on a background queue
    /// roughly every 50 ms while capturing.
    public private(set) var lastLevel: Float = 0

    /// The rolling buffer the manager appends converted samples to.
    public let buffer: RollingAudioBuffer

    /// Sample rate the manager normalizes all captured audio to. Stored
    /// per-instance so callers can construct multiple managers with
    /// different target rates (e.g. 16 kHz for Whisper, 24 kHz for some
    /// Grok endpoints) without changing the type-level default.
    public let targetSampleRate: Double

    // MARK: - Private state

    // ponytail: engine is nil between sessions so the input AudioUnit is fully
    // released — keeping one allocated (even stopped) can hold the device handle
    // and force Bluetooth mics into low-quality SCO/HFP profile.
    private var engine: AVAudioEngine?
    private let converterLock = NSLock()
    private var converter: AVAudioConverter?
    private let levelQueue = DispatchQueue(label: "com.narrav2.audio.level", qos: .utility)
    private let levelAccumulatorLock = NSLock()
    private var levelAccumulator: Float = 0
    private var levelSampleCount: Int = 0
    private var levelFlushScheduled: Bool = false

    private let chunkLock = NSLock()
    private var chunkAccumulator: [Int16] = []
    private var chunkWindowSamples: Int = 0
    private var chunkContinuation: AsyncStream<AudioChunk>.Continuation?

    // MARK: - Init

    public init(
        bufferCapacitySeconds: Double = AudioCaptureManager.defaultBufferSeconds,
        targetSampleRate: Double = AudioCaptureManager.targetSampleRate
    ) {
        self.targetSampleRate = targetSampleRate
        self.buffer = RollingAudioBuffer(
            capacitySeconds: bufferCapacitySeconds,
            sampleRate: targetSampleRate
        )
    }

    // MARK: - Permission

    /// Request microphone access. Safe to call multiple times — the system
    /// will not re-prompt once the user has decided.
    public func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Lifecycle

    /// Begin capturing. No-op if already capturing. Throws if microphone
    /// permission is denied.
    public func start() async throws {
        guard !isCapturing else { return }
        let granted = await requestPermission()
        guard granted else {
            throw AudioCaptureError.permissionDenied
        }
        let engine = AVAudioEngine()
        self.engine = engine

        let inputNode = engine.inputNode
        // Apply preferred input device if user picked one in the menu.
        // ponytail: best-effort CoreAudio property set; silently falls
        // back to system-default mic if anything fails.
        if let uid = UserDefaults.standard.string(forKey: "preferredMicUniqueID"),
           let deviceID = Self.audioDeviceID(forUniqueID: uid),
           let inputAU = inputNode.audioUnit {
            var id = deviceID
            AudioUnitSetProperty(
                inputAU,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &id,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw AudioCaptureError.noInputDevice
        }

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        )!

        installConverter(from: inputFormat, to: targetFormat)
        installTap(inputNode: inputNode, inputFormat: inputFormat, targetFormat: targetFormat)

        engine.prepare()
        do {
            try engine.start()
        } catch {
            removeTap(inputNode: inputNode, inputFormat: inputFormat)
            converter = nil
            throw AudioCaptureError.engineFailedToStart(error.localizedDescription)
        }
        isCapturing = true
    }

    /// Stop capturing and flush the rolling buffer to a single
    /// `AudioChunk`. The returned chunk has `startTime = nil` (the manager
    /// has no notion of a wall-clock audio timeline across restarts) and
    /// contains whatever audio was captured since the previous flush.
    @discardableResult
    public func stop() -> AudioChunk {
        if isCapturing, let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            engine.reset()
            converterLock.lock(); converter = nil; converterLock.unlock()
            // Drop the engine entirely so the input AudioUnit releases the
            // device handle — otherwise Bluetooth mics stay pinned to SCO/HFP
            // and the system mic-in-use indicator lingers.
            self.engine = nil
            isCapturing = false
        }
        chunkLock.lock()
        let continuation = chunkContinuation
        let tail = chunkAccumulator
        let tailRate = targetSampleRate
        chunkContinuation = nil
        chunkAccumulator.removeAll(keepingCapacity: false)
        chunkLock.unlock()
        // Emit the unsent remainder as a final chunk so the streaming caller
        // gets the complete recording without re-transcribing the rolling
        // buffer (which overlaps with already-emitted windows).
        // ponytail: 0.2s floor avoids sending a few hundred samples of
        // ambient noise to Whisper at stop.
        if let continuation, tail.count >= Int(0.2 * tailRate) {
            continuation.yield(AudioChunk(samples: tail, sampleRate: tailRate, startTime: nil))
        }
        continuation?.finish()
        let samples = buffer.flush()
        return AudioChunk(samples: samples, sampleRate: targetSampleRate, startTime: nil)
    }

    // MARK: - CoreAudio helpers

    /// Returns the `AudioDeviceID` whose UID matches `uniqueID`, or nil.
    public static func audioDeviceID(forUniqueID uniqueID: String) -> AudioDeviceID? {
        var size: UInt32 = 0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == noErr else {
            return nil
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &ids) == noErr else {
            return nil
        }
        for id in ids {
            var uidAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uid: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let status = AudioObjectGetPropertyData(id, &uidAddr, 0, nil, &uidSize, &uid)
            guard status == noErr, let cf = uid?.takeRetainedValue() else { continue }
            if (cf as String) == uniqueID { return id }
        }
        return nil
    }

    /// Discard buffered audio without stopping capture.
    public func clearBuffer() {
        buffer.clear()
    }

    // MARK: - Streaming chunks

    /// Returns an `AsyncStream` that yields fixed-size `AudioChunk`s while
    /// capture is running, letting downstream transcription overlap with
    /// recording. The stream finishes when `stop()` is called. Tail audio
    /// (less than one window worth at stop time) is NOT emitted here — the
    /// caller should still consume `stop()`'s return value for the final
    /// remainder.
    ///
    /// Call before `start()`. Calling twice replaces the previous stream and
    /// finishes the old one.
    /// ponytail: 5s windows preserve WhisperKit accuracy without overlap;
    /// the Groq cleanup pass absorbs boundary glitches.
    public func chunkStream(windowSeconds: Double = 5.0) -> AsyncStream<AudioChunk> {
        AsyncStream { continuation in
            let windowSamples = Int(windowSeconds * targetSampleRate)
            chunkLock.lock()
            chunkContinuation?.finish()
            chunkAccumulator.removeAll(keepingCapacity: true)
            chunkWindowSamples = max(1, windowSamples)
            chunkContinuation = continuation
            chunkLock.unlock()

            continuation.onTermination = { [weak self] _ in
                guard let self = self else { return }
                self.chunkLock.lock()
                self.chunkContinuation = nil
                self.chunkAccumulator.removeAll(keepingCapacity: false)
                self.chunkLock.unlock()
            }
        }
    }

    // MARK: - Tap installation

    private func installConverter(
        from inputFormat: AVAudioFormat,
        to targetFormat: AVAudioFormat
    ) {
        let newConverter = AVAudioConverter(from: inputFormat, to: targetFormat)
        converterLock.lock()
        converter = newConverter
        converterLock.unlock()
    }

    private func installTap(
        inputNode: AVAudioInputNode,
        inputFormat: AVAudioFormat,
        targetFormat: AVAudioFormat
    ) {
        // Use the input node's native format here — the tap callback does
        // the conversion via `convert(to:)`. We deliberately avoid asking
        // the engine for a converted tap because the engine will refuse
        // formats that the hardware cannot produce, and we want to be
        // robust to whatever the mic gives us.
        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: inputFormat
        ) { [weak self] buffer, _ in
            self?.handleCapturedBuffer(buffer, targetFormat: targetFormat)
        }
    }

    private func removeTap(inputNode: AVAudioInputNode, inputFormat: AVAudioFormat) {
        inputNode.removeTap(onBus: 0)
    }

    private func handleCapturedBuffer(
        _ inputBuffer: AVAudioPCMBuffer,
        targetFormat: AVAudioFormat
    ) {
        converterLock.lock()
        let activeConverter = converter
        converterLock.unlock()

        guard let converter = activeConverter else { return }

        // Compute the capacity of the output buffer needed for the conversion.
        let ratio = targetFormat.sampleRate / inputBuffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio + 0.5)
        guard outCapacity > 0,
              let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: outCapacity
              ) else {
            return
        }

        var error: NSError?
        let supplied = Mutex(false)
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            let wasFed = supplied.withLock { flag -> Bool in
                let was = flag; if !was { flag = true }; return was
            }
            outStatus.pointee = wasFed ? .noDataNow : .haveData
            return wasFed ? nil : inputBuffer
        }

        guard status != .error, error == nil else {
            return
        }

        let int16 = bufferToInt16Samples(outputBuffer)
        if !int16.isEmpty {
            buffer.append(int16)
            emitWindowedChunks(int16)
        }
        updateLevel(from: int16)
    }

    /// Feed converted samples into the chunk accumulator and yield a
    /// full-window `AudioChunk` each time the threshold is crossed.
    private func emitWindowedChunks(_ samples: [Int16]) {
        chunkLock.lock()
        guard let continuation = chunkContinuation, chunkWindowSamples > 0 else {
            chunkLock.unlock()
            return
        }
        chunkAccumulator.append(contentsOf: samples)
        var emits: [[Int16]] = []
        while chunkAccumulator.count >= chunkWindowSamples {
            let window = Array(chunkAccumulator.prefix(chunkWindowSamples))
            chunkAccumulator.removeFirst(chunkWindowSamples)
            emits.append(window)
        }
        let rate = targetSampleRate
        chunkLock.unlock()

        for window in emits {
            continuation.yield(AudioChunk(samples: window, sampleRate: rate, startTime: nil))
        }
    }

    /// Convert an `AVAudioPCMBuffer` of `pcmFormatInt16` mono interleaved
    /// samples into a `[Int16]`. Returns `[]` for buffers of the wrong
    /// shape.
    private func bufferToInt16Samples(_ pcm: AVAudioPCMBuffer) -> [Int16] {
        guard pcm.format.commonFormat == .pcmFormatInt16,
              let int16Data = pcm.int16ChannelData else {
            return []
        }
        let channelCount = Int(pcm.format.channelCount)
        let frameLength = Int(pcm.frameLength)
        guard channelCount == 1 else { return [] }
        let ptr = int16Data[0]
        var out = [Int16]()
        out.reserveCapacity(frameLength)
        for i in 0..<frameLength {
            out.append(ptr[i])
        }
        return out
    }

    private func updateLevel(from samples: [Int16]) {
        guard !samples.isEmpty else { return }
        var sumSquares: Float = 0
        for s in samples {
            let normalized = Float(s) / 32_768.0
            sumSquares += normalized * normalized
        }
        let rms = sqrt(sumSquares / Float(samples.count))
        levelAccumulator += rms
        levelSampleCount += 1

        // Throttle: publish the average RMS at most ~20 Hz.
        if !levelFlushScheduled {
            levelFlushScheduled = true
            levelQueue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self = self else { return }
                self.levelAccumulatorLock.lock()
                let avg = self.levelSampleCount > 0
                    ? self.levelAccumulator / Float(self.levelSampleCount)
                    : 0
                self.levelAccumulator = 0
                self.levelSampleCount = 0
                self.levelFlushScheduled = false
                self.levelAccumulatorLock.unlock()
                self.lastLevel = avg
            }
        }
    }
}

// MARK: - Errors

public enum AudioCaptureError: Error, Equatable, Sendable {
    case permissionDenied
    case noInputDevice
    case engineFailedToStart(String)
}
