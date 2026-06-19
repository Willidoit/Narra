import XCTest
@testable import Narra

final class SmartContextTests: XCTestCase {

    func testKnownCodeEditorsMatch() {
        XCTAssertTrue(SmartContext.isFrontmostAppCodeEditor(frontmost: "com.apple.dt.Xcode"))
        XCTAssertTrue(SmartContext.isFrontmostAppCodeEditor(frontmost: "com.microsoft.VSCode"))
        XCTAssertTrue(SmartContext.isFrontmostAppCodeEditor(frontmost: "dev.warp.Warp"))
        XCTAssertTrue(SmartContext.isFrontmostAppCodeEditor(frontmost: "com.googlecode.iterm2"))
    }

    func testJetBrainsPrefixMatch() {
        XCTAssertTrue(SmartContext.isFrontmostAppCodeEditor(frontmost: "com.jetbrains.intellij"))
        XCTAssertTrue(SmartContext.isFrontmostAppCodeEditor(frontmost: "com.jetbrains.pycharm"))
        XCTAssertTrue(SmartContext.isFrontmostAppCodeEditor(frontmost: "com.jetbrains.WebStorm"))
    }

    func testNonCodeEditorsDoNotMatch() {
        XCTAssertFalse(SmartContext.isFrontmostAppCodeEditor(frontmost: "com.apple.mail"))
        XCTAssertFalse(SmartContext.isFrontmostAppCodeEditor(frontmost: "com.tinyspeck.slackmacgap"))
        XCTAssertFalse(SmartContext.isFrontmostAppCodeEditor(frontmost: nil))
    }

    func testPrefixDoesNotMatchUnrelatedAppsThatShareBundlePrefix() {
        // "com.apple.dt.XcodeBeta" would be wrong to skip cleanup for some
        // hypothetical sibling. The prefix-match requires a "." separator so
        // "com.apple.dt.Xcode" never matches "com.apple.dt.XcodeBeta" as a
        // substring — only as a parent.
        XCTAssertFalse(SmartContext.isFrontmostAppCodeEditor(frontmost: "com.apple.dt.XcodeOther"))
    }

    func testEscalateForLengthBumpsPastThirtySeconds() {
        XCTAssertEqual(SmartContext.escalateForLength(.light, durationSeconds: 15), .light)
        XCTAssertEqual(SmartContext.escalateForLength(.light, durationSeconds: 35), .medium)
        XCTAssertEqual(SmartContext.escalateForLength(.medium, durationSeconds: 35), .high)
        XCTAssertEqual(SmartContext.escalateForLength(.high, durationSeconds: 60), .high)
        XCTAssertEqual(SmartContext.escalateForLength(.none, durationSeconds: 60), .none)
    }
}
