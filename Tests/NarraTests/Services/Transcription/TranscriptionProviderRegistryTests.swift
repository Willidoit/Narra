import XCTest
@testable import Narra

final class TranscriptionProviderRegistryTests: XCTestCase {
    func testWiredAndStubbedProviderStatuses() {
        let byID = Dictionary(
            uniqueKeysWithValues: TranscriptionProviderRegistry.all.map { ($0.id, $0) }
        )

        for id in ProviderID.allCases {
            XCTAssertNotNil(byID[id], "Registry missing entry for \(id.rawValue)")
        }

        for id in [ProviderID.groq, .openAI, .deepgram, .elevenLabs, .whisperKit, .appleSpeech] {
            XCTAssertEqual(byID[id]?.status, .wired, "\(id.rawValue) should be wired")
        }

        for id in [ProviderID.whisperCpp, .parakeet] {
            XCTAssertEqual(byID[id]?.status, .stubbed, "\(id.rawValue) should be stubbed")
        }
    }
}
