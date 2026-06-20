import XCTest
@testable import Narra

final class TranscriptionProviderRegistryTests: XCTestCase {
    func testAllProvidersWiredAndPresent() {
        let byID = Dictionary(
            uniqueKeysWithValues: TranscriptionProviderRegistry.all.map { ($0.id, $0) }
        )

        for id in ProviderID.allCases {
            XCTAssertNotNil(byID[id], "Registry missing entry for \(id.rawValue)")
            XCTAssertEqual(byID[id]?.status, .wired, "\(id.rawValue) should be wired")
        }
    }
}
