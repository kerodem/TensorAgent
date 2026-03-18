import SwiftUI
import AppKit

struct TerminalSurfaceView: NSViewRepresentable {
    let output: String
    let onInput: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onInput: onInput)
    }

    func makeNSView(context: Context) -> TerminalContainerView {
        let view = TerminalContainerView()
        view.textView.onInput = { text in
            context.coordinator.onInput(text)
        }
        view.applyTheme()
        return view
    }

    func updateNSView(_ nsView: TerminalContainerView, context: Context) {
        context.coordinator.onInput = onInput

        if output.hasPrefix(context.coordinator.renderedOutput) {
            let suffix = output.dropFirst(context.coordinator.renderedOutput.count)
            if !suffix.isEmpty {
                nsView.append(String(suffix))
            }
        } else {
            nsView.replaceAll(with: output)
        }

        context.coordinator.renderedOutput = output
        nsView.scrollToBottom()

        if !context.coordinator.focusedOnce, nsView.window != nil {
            nsView.window?.makeFirstResponder(nsView.textView)
            context.coordinator.focusedOnce = true
        }
    }

    final class Coordinator {
        var renderedOutput: String = ""
        var onInput: (String) -> Void
        var focusedOnce: Bool = false

        init(onInput: @escaping (String) -> Void) {
            self.onInput = onInput
        }
    }
}

final class TerminalContainerView: NSView {
    let scrollView: NSScrollView
    let textView: TerminalTextView

    override init(frame frameRect: NSRect) {
        textView = TerminalTextView(frame: .zero)
        scrollView = NSScrollView(frame: .zero)
        super.init(frame: frameRect)

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = true
        textView.isRichText = false
        textView.isSelectable = true
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func applyTheme() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.11, alpha: 1).cgColor

        textView.drawsBackground = true
        textView.backgroundColor = NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.11, alpha: 1)
        textView.textColor = NSColor(calibratedRed: 0.88, green: 0.91, blue: 0.89, alpha: 1)
        textView.insertionPointColor = NSColor(calibratedRed: 0.42, green: 0.93, blue: 0.58, alpha: 1)
        textView.font = NSFont(name: "Menlo", size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    }

    func append(_ text: String) {
        guard let storage = textView.textStorage, !text.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: textView.font as Any,
            .foregroundColor: textView.textColor as Any
        ]
        storage.append(NSAttributedString(string: text, attributes: attrs))
    }

    func replaceAll(with text: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: textView.font as Any,
            .foregroundColor: textView.textColor as Any
        ]
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attrs))
    }

    func scrollToBottom() {
        let len = textView.string.count
        guard len > 0 else { return }
        textView.scrollRangeToVisible(NSRange(location: len - 1, length: 1))
    }
}

final class TerminalTextView: NSTextView {
    var onInput: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), let control = controlCharacter(for: event) {
            onInput?(control)
            return
        }

        if event.modifierFlags.contains(.command) {
            if let key = event.charactersIgnoringModifiers?.lowercased(), key == "v" {
                let pasted = NSPasteboard.general.string(forType: .string) ?? ""
                if !pasted.isEmpty {
                    onInput?(pasted)
                }
                return
            }

            super.keyDown(with: event)
            return
        }

        if let special = specialSequence(for: event) {
            onInput?(special)
            return
        }

        if let chars = event.characters, !chars.isEmpty {
            onInput?(chars)
            return
        }

        super.keyDown(with: event)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if let string = insertString as? String {
            onInput?(string)
            return
        }
        if let attributed = insertString as? NSAttributedString {
            onInput?(attributed.string)
            return
        }

        super.insertText(insertString, replacementRange: replacementRange)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    private func specialSequence(for event: NSEvent) -> String? {
        switch event.keyCode {
        case 36, 76:
            return "\r"
        case 48:
            return "\t"
        case 51:
            return "\u{7f}"
        case 53:
            return "\u{1b}"
        case 123:
            return "\u{1b}[D"
        case 124:
            return "\u{1b}[C"
        case 125:
            return "\u{1b}[B"
        case 126:
            return "\u{1b}[A"
        default:
            return nil
        }
    }

    private func controlCharacter(for event: NSEvent) -> String? {
        guard let chars = event.charactersIgnoringModifiers, let scalar = chars.unicodeScalars.first else {
            return nil
        }

        let value = scalar.value
        if value >= 64, value <= 95 {
            return String(decoding: [UInt8(value - 64)], as: UTF8.self)
        }

        if value >= 97, value <= 122 {
            return String(decoding: [UInt8(value - 96)], as: UTF8.self)
        }

        return nil
    }
}
