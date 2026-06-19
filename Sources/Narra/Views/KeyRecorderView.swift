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

        // Background fill — matches the glass-card recessed input style.
        let bgPath = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        NSColor.white.withAlphaComponent(0.05).setFill()
        bgPath.fill()

        let label = isRecordingKeys
            ? "Press a key, or hold then release a modifier…"
            : (currentBinding.keyChar == nil && currentBinding.modifierFlags == 0
               ? "Click to record"
               : currentBinding.displayString)

        let useMono = !isRecordingKeys && (currentBinding.keyChar != nil || currentBinding.modifierFlags != 0)
        let primary: NSFont? = useMono
            ? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            : NSFont.systemFont(ofSize: 11)
        let font = primary ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let color: NSColor = isRecordingKeys
            ? NSColor.white.withAlphaComponent(0.55)
            : NSColor(red: 0.949, green: 0.945, blue: 0.925, alpha: 1.0) // matches Palette.darkInk
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let size = str.size()
        let rect = NSRect(
            x: 10,
            y: (bounds.height - size.height) / 2,
            width: bounds.width - 20,
            height: size.height
        )
        str.draw(in: rect)

        let borderColor: NSColor = isRecordingKeys
            ? NSColor.white.withAlphaComponent(0.55)
            : NSColor.white.withAlphaComponent(0.12)
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
