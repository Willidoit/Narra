import SwiftUI
import AVFoundation

// MARK: - Microphone enumeration

@MainActor
final class MicrophoneList: ObservableObject {
    @Published var devices: [AVCaptureDevice] = []
    @Published var selectedUID: String? = nil

    init() {
        refresh()
    }

    func refresh() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        devices = session.devices
        selectedUID = UserDefaults.standard.string(forKey: "preferredMicUniqueID")
    }
}
