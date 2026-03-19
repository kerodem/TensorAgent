import Foundation

@MainActor
final class PaneSession: ObservableObject, Identifiable {
    let id = UUID()
    let slot: Int
    let config: PaneConfig

    @Published var output: String = ""
    @Published var state: PaneState = .idle

    private let outputLimit = 300_000
    private let helpCommandToken = ",help,,"
    private var runner: PTYProcess?
    private var inputLineBuffer = ""

    init(slot: Int, config: PaneConfig) {
        self.slot = slot
        self.config = config
    }

    func launch(command: String, cwd: String) {
        stop()

        state = .launching
        output = ""

        let process = PTYProcess()
        runner = process

        process.onOutput = { [weak self] chunk in
            Task { @MainActor in
                self?.append(chunk)
            }
        }

        process.onExit = { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                if case .failed = self.state {
                    return
                }
                self.state = .exited(status)
            }
        }

        do {
            try process.start(command: command, cwd: cwd)
            state = .running
            append("[started] \(command)\n")
        } catch {
            state = .failed(error.localizedDescription)
            append("[failed] \(error.localizedDescription)\n")
        }
    }

    func sendInput(_ text: String) {
        guard runner != nil else { return }

        if text == "\u{7f}" {
            if !inputLineBuffer.isEmpty {
                inputLineBuffer.removeLast()
            }
            runner?.write(text)
            return
        }

        if text == "\r" || text == "\n" {
            let raw = inputLineBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if raw == helpCommandToken {
                runner?.write("\u{15}")
                append(helpIndexText())
                inputLineBuffer = ""
                return
            }

            inputLineBuffer = ""
            runner?.write(text)
            return
        }

        if text.hasPrefix("\u{1b}") || text.contains("\u{03}") || text.contains("\u{04}") {
            inputLineBuffer = ""
            runner?.write(text)
            return
        }

        if text.rangeOfCharacter(from: .newlines) != nil {
            inputLineBuffer = ""
        } else if text.rangeOfCharacter(from: .controlCharacters) == nil {
            inputLineBuffer += text
            if inputLineBuffer.count > 256 {
                inputLineBuffer.removeFirst(inputLineBuffer.count - 256)
            }
        }

        runner?.write(text)
    }

    func interrupt() {
        guard runner != nil else { return }
        runner?.interrupt()
    }

    func stop() {
        runner?.stop()
        runner = nil

        if case .running = state {
            state = .exited(0)
        }
    }

    func clear() {
        output = ""
        inputLineBuffer = ""
    }

    private func append(_ text: String) {
        output += text
        if output.count > outputLimit {
            output.removeFirst(output.count - outputLimit)
        }
    }

    private func helpIndexText() -> String {
        [
            "",
            "TensorAgent Help Index",
            "======================",
            "Command:",
            "  ,help,,      Show this help index",
            "",
            "Basics:",
            "  - Click a pane to focus it.",
            "  - Type directly to the active PTY session.",
            "  - Use top-right Settings to configure provider/model/args.",
            "  - Use Ctrl+C to interrupt an active process.",
            "",
            "Docs:",
            "  https://blacktensor.net/docs",
            ""
        ].joined(separator: "\n")
    }
}
