import XCTest
@testable import NarraV2

final class AudioSampleConverterTests: XCTestCase {

    // MARK: - Int16 -> Float

    func test_int16ToFloat_zeroMapsToZero() {
        XCTAssertEqual(AudioSampleConverter.float(from: [0]), [0.0])
    }

    func test_int16ToFloat_positiveMaxMapsToOne() {
        XCTAssertEqual(AudioSampleConverter.float(from: [Int16.max]), [1.0])
    }

    func test_int16ToFloat_negativeMinMapsToNegativeOne() {
        XCTAssertEqual(AudioSampleConverter.float(from: [Int16.min]), [-1.0])
    }

    func test_int16ToFloat_emptyInputReturnsEmpty() {
        XCTAssertEqual(AudioSampleConverter.float(from: []), [])
    }

    func test_int16ToFloat_arbitraryValue() {
        // 16384 / 32768 = 0.5
        let result = AudioSampleConverter.float(from: [16384])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], 0.5, accuracy: 0.0001)
    }

    // MARK: - Float -> Int16

    func test_floatToInt16_zeroMapsToZero() {
        XCTAssertEqual(AudioSampleConverter.int16(from: [0.0]), [0])
    }

    func test_floatToInt16_oneMapsToPositiveMax() {
        XCTAssertEqual(AudioSampleConverter.int16(from: [1.0]), [Int16.max])
    }

    func test_floatToInt16_negativeOneMapsToNegativeMin() {
        XCTAssertEqual(AudioSampleConverter.int16(from: [-1.0]), [Int16.min])
    }

    func test_floatToInt16_clampsAboveOne() {
        XCTAssertEqual(AudioSampleConverter.int16(from: [2.0]), [Int16.max])
    }

    func test_floatToInt16_clampsBelowNegativeOne() {
        XCTAssertEqual(AudioSampleConverter.int16(from: [-2.0]), [Int16.min])
    }

    func test_floatToInt16_emptyInputReturnsEmpty() {
        XCTAssertEqual(AudioSampleConverter.int16(from: []), [])
    }

    // MARK: - Round-trip

    func test_roundTrip_int16ToFloatToInt16_isLossyOnlyForTruncation() {
        // Quantize a known value to int16 then back; we should land within 1 LSB.
        let original: [Float] = [0.25, -0.5, 0.75, -0.125]
        let asInt16 = AudioSampleConverter.int16(from: original)
        let back = AudioSampleConverter.float(from: asInt16)

        for (a, b) in zip(original, back) {
            let lsb: Float = 1.0 / 32_768.0
            XCTAssertEqual(a, b, accuracy: lsb)
        }
    }
}
