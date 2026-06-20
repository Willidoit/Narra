import XCTest
import Foundation
@testable import Narra

final class LocalModelManagerTests: XCTestCase {

    var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("narrav2-models-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func test_init_createsBaseDirectory() throws {
        let manager = LocalModelManager(baseDirectory: tmpDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpDir.path))
        _ = manager
    }

    func test_localURL_isNilWhenNotDownloaded() {
        let manager = LocalModelManager(baseDirectory: tmpDir)
        let spec = LocalModelManager.ModelSpec(
            key: "test-model",
            displayName: "Test",
            url: URL(string: "https://example.com/model.bin")!,
            sizeBytes: 1000
        )
        XCTAssertNil(manager.localURL(for: spec))
        XCTAssertFalse(manager.isDownloaded(spec))
    }

    func test_localURL_isReturnedAfterFakeDownload() throws {
        let manager = LocalModelManager(baseDirectory: tmpDir)
        let spec = LocalModelManager.ModelSpec(
            key: "test-model",
            displayName: "Test",
            url: URL(string: "https://example.com/model.bin")!,
            sizeBytes: 1000
        )
        // Simulate a downloaded file
        let dest = tmpDir.appendingPathComponent("\(spec.key).bin")
        try Data([0x00, 0x01, 0x02]).write(to: dest)

        XCTAssertTrue(manager.isDownloaded(spec))
        XCTAssertEqual(manager.localURL(for: spec), dest)
    }

    func test_defaults_areWhisperBaseAndLlama3B() {
        XCTAssertEqual(LocalModelManager.defaultWhisper.key, "openai_whisper-base")
        XCTAssertTrue(LocalModelManager.defaultWhisper.url.absoluteString.contains("whisper"))
        XCTAssertEqual(LocalModelManager.defaultLLM.key, "llama-3.2-1b")
        XCTAssertTrue(LocalModelManager.defaultLLM.url.absoluteString.contains("Llama"))
    }

    func test_localModelError_isEquatable() {
        XCTAssertEqual(
            LocalModelError.downloadFailed("k", 500),
            .downloadFailed("k", 500)
        )
        XCTAssertNotEqual(
            LocalModelError.downloadFailed("k", 500),
            .downloadFailed("k", 503)
        )
        XCTAssertEqual(
            LocalModelError.modelNotFound("k"),
            .modelNotFound("k")
        )
    }
}

final class ServiceOrchestratorTests: XCTestCase {

    func test_mode_cloudOnly_picksCloudEvenWithoutLocal() {
        let orch = ServiceOrchestrator(
            configuration: ServiceOrchestrator.Configuration(mode: .cloudOnly),
            modelManager: LocalModelManager(baseDirectory: makeTmp())
        )
        XCTAssertEqual(orch.pickOrder(), .cloud)
    }

    func test_mode_localOnly_picksLocal() {
        let orch = ServiceOrchestrator(
            configuration: ServiceOrchestrator.Configuration(mode: .localOnly),
            modelManager: LocalModelManager(baseDirectory: makeTmp())
        )
        XCTAssertEqual(orch.pickOrder(), .local)
    }

    func test_mode_automatic_networkUp_picksCloud() {
        let orch = ServiceOrchestrator(
            configuration: ServiceOrchestrator.Configuration(mode: .automatic),
            modelManager: LocalModelManager(baseDirectory: makeTmp())
        )
        // No path updates yet -> default to "reachable" -> cloud
        XCTAssertEqual(orch.pickOrder(), .cloud)
    }

    func test_isLocalAvailable_falseWhenNothingDownloaded() {
        let orch = ServiceOrchestrator(
            configuration: ServiceOrchestrator.Configuration(),
            modelManager: LocalModelManager(baseDirectory: makeTmp())
        )
        XCTAssertFalse(orch.isLocalAvailable)
    }

    func test_isLocalAvailable_trueWhenWhisperDownloaded() throws {
        let tmp = makeTmp()
        let whisperDest = tmp.appendingPathComponent("\(LocalModelManager.defaultWhisper.key).bin")
        try Data([0x00]).write(to: whisperDest)

        let orch = ServiceOrchestrator(
            configuration: ServiceOrchestrator.Configuration(),
            modelManager: LocalModelManager(baseDirectory: tmp)
        )
        XCTAssertTrue(orch.isLocalAvailable)
    }

    func test_localTranscriber_throwsOnEmptyAudio() async {
        let service = LocalTranscriptionService(
            configuration: LocalTranscriptionService.Configuration(
                modelManager: LocalModelManager(baseDirectory: makeTmp())
            )
        )
        let chunk = AudioChunk(samples: [], sampleRate: 16_000)
        do {
            _ = try await service.transcribe(audio: chunk)
            XCTFail("Expected emptyAudio")
        } catch {
            XCTAssertEqual(error as? TranscriptionError, .emptyAudio)
        }
    }

    func test_localProcessor_throwsOnEmptySegments() async {
        let service = LocalPostProcessingService(
            configuration: LocalPostProcessingService.Configuration(
                modelManager: LocalModelManager(baseDirectory: makeTmp())
            )
        )
        do {
            _ = try await service.process(segments: [])
            XCTFail("Expected serviceError")
        } catch {
            XCTAssertTrue(error is PostProcessingError)
        }
    }

    // MARK: - helpers

    private func makeTmp() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("narrav2-orch-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
