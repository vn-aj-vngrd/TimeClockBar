import AppKit
import SwiftUI

struct HotkeyRecorderButton: View {
    let label: String
    @Binding var isRecording: Bool
    let onRecord: (UInt32, NSEvent.ModifierFlags) -> Void
    @State private var recordingLabel = "Listening..."

    private let allowedModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    var body: some View {
        HStack(spacing: 6) {
            Text(isRecording ? recordingLabel : label)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(isRecording ? ChromeColor.primaryText : ChromeColor.secondaryText)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 96, alignment: .trailing)

            if isRecording {
                Button("Clear") {
                    stopRecording()
                }
                .buttonStyle(.settingsControl)
                .fixedSize(horizontal: true, vertical: false)
            } else {
                Button("Change") {
                    startRecording()
                }
                .buttonStyle(.settingsControl)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .background {
            HotkeyCaptureView(
                isActive: isRecording,
                onKeyDown: handleKeyDown,
                onModifierChange: updateRecordingLabel
            )
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        recordingLabel = "Listening..."
        isRecording = true
    }

    private func stopRecording() {
        recordingLabel = "Listening..."
        isRecording = false
    }

    private func handleKeyDown(_ event: NSEvent) {
        if event.keyCode == 53 {
            stopRecording()
            return
        }

        let modifiers = event.modifierFlags.intersection(allowedModifiers)
        recordingLabel = HotkeyFormatting.label(keyCode: UInt32(event.keyCode), modifiers: modifiers)

        guard !modifiers.isEmpty else {
            NSSound.beep()
            return
        }

        onRecord(UInt32(event.keyCode), modifiers)
        stopRecording()
    }

    private func updateRecordingLabel(modifiers: NSEvent.ModifierFlags) {
        let modifierLabel = HotkeyFormatting.modifierLabel(modifiers.intersection(allowedModifiers))
        recordingLabel = modifierLabel.isEmpty ? "Listening..." : "\(modifierLabel)..."
    }
}

private struct HotkeyCaptureView: NSViewRepresentable {
    let isActive: Bool
    let onKeyDown: (NSEvent) -> Void
    let onModifierChange: (NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onKeyDown = onKeyDown
        view.onModifierChange = onModifierChange
        return view
    }

    func updateNSView(_ view: CaptureView, context: Context) {
        view.onKeyDown = onKeyDown
        view.onModifierChange = onModifierChange

        guard isActive else { return }

        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
    }

    final class CaptureView: NSView {
        var onKeyDown: ((NSEvent) -> Void)?
        var onModifierChange: ((NSEvent.ModifierFlags) -> Void)?

        override var acceptsFirstResponder: Bool {
            true
        }

        override func keyDown(with event: NSEvent) {
            onKeyDown?(event)
        }

        override func flagsChanged(with event: NSEvent) {
            onModifierChange?(event.modifierFlags)
        }
    }
}
