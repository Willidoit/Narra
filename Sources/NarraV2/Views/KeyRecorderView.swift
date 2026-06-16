import SwiftUI
import AppKit

// MARK: - KeyRecorderView

/// SwiftUI wrapper around `KeyRecorderNSView` for capturing keyboard shortcuts.
/// Click to enter recording state, then press a key combo or hold+release modifiers.
struct KeyRecorderView: NSViewRepresentable {
    @Binding var binding: KeyBinding

    func makeNSView(context: Context) -> KeyRecorderNSView {
        KeyRecorderNSView()
    }

    func updateNSView(_ nsView: KeyRecorderNSView, context: Context) {
        if !nsView.isRecordingKeys {
            nsView.currentBinding = binding
            nsView.needsDisplay = true
        }
        nsView.onCommit = { newBinding in
            binding = newBinding
        }
    }
}

// MARK: - KeyRecorderNSView

final class KeyRecorderNSView: NSView {
    var currentBinding: KeyBinding = KeyBinding(keyChar: nil, modifierFlags: 0)
    var onCommit: ((KeyBinding) -> Void)?
    private(set) var isRecordingKeys = false
    private var peakFlags: NSEvent.ModifierFlags = []

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let label = isRecordingKeys
            ? "Press a key, or hold then release a modifier…"
            : (currentBinding.keyChar == nil && currentBinding.modifierFlags == 0
               ? "Click to record"
               : currentBinding.displayString)

        let color: NSColor = isRecordingKeys ? .secondaryLabelColor : .labelColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: color
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let size = str.size()
        let rect = NSRect(
            x: 8,
            y: (bounds.height - size.height) / 2,
            width: bounds.width - 16,
            height: size.height
        )
        str.draw(in: rect)

        let borderColor: NSColor = isRecordingKeys ? .controlAccentColor : .separatorColor
        borderColor.setStroke()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        path.lineWidth = isRecordingKeys ? 2 : 1
        path.stroke()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 140, height: 28)
    }

    override func mouseDown(with event: NSEvent) {
        guard !isRecordingKeys else { return }
        window?.makeFirstResponder(self)
        isRecordingKeys = true
        peakFlags = []
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecordingKeys, !event.isARepeat else { return }
        let relevantBits: NSEvent.ModifierFlags = [.function, .command, .option, .control, .shift]
        let mods = event.modifierFlags.intersection(relevantBits)
        if let first = event.charactersIgnoringModifiers?.first {
            commit(KeyBinding(keyChar: String(first).lowercased(), modifierFlags: mods.rawValue))
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecordingKeys else { return }
        let relevantBits: NSEvent.ModifierFlags = [.function, .command, .option, .control, .shift]
        let current = event.modifierFlags.intersection(relevantBits)
        if !current.isEmpty {
            peakFlags = current
        } else if !peakFlags.isEmpty {
            commit(KeyBinding(keyChar: nil, modifierFlags: peakFlags.rawValue))
        }
    }

    private func commit(_ newBinding: KeyBinding) {
        isRecordingKeys = false
        currentBinding = newBinding
        needsDisplay = true
        onCommit?(newBinding)
    }
}
