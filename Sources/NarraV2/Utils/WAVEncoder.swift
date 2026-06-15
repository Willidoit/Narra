import Foundation

/// Encodes a mono Int16 PCM buffer into a 16-bit PCM WAV file (RIFF).
///
/// The output is a canonical, in-memory WAV: 44-byte RIFF header followed
/// by interleaved (well, mono) little-endian Int16 samples. The format
/// matches what every major STT engine (Whisper, Grok, MLX) accepts as
/// `audio/wav`.
public enum WAVEncoder {

    public static func encode(samples: [Int16], sampleRate: Double) -> Data {
        let byteRate = UInt32(sampleRate) * 2 // mono * 16-bit
        let dataSize = UInt32(samples.count * 2)
        var data = Data()
        data.reserveCapacity(44 + Int(dataSize))

        // RIFF header
        data.append("RIFF".data(using: .ascii)!)
        data.appendLE(UInt32(36 + dataSize))
        data.append("WAVE".data(using: .ascii)!)

        // fmt chunk
        data.append("fmt ".data(using: .ascii)!)
        data.appendLE(UInt32(16))           // PCM chunk size
        data.appendLE(UInt16(1))            // PCM format
        data.appendLE(UInt16(1))            // channels
        data.appendLE(UInt32(sampleRate))   // sample rate
        data.appendLE(byteRate)             // byte rate
        data.appendLE(UInt16(2))            // block align (channels * bytes per sample)
        data.appendLE(UInt16(16))           // bits per sample

        // data chunk
        data.append("data".data(using: .ascii)!)
        data.appendLE(dataSize)

        // samples
        samples.withUnsafeBufferPointer { buf in
            let raw = UnsafeRawBufferPointer(buf)
            data.append(contentsOf: raw)
        }
        return data
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { buf in
            append(contentsOf: buf)
        }
    }
}
