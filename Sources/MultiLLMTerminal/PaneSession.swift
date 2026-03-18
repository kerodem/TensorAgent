import Foundation

@MainActor
final class PaneSession: ObservableObject, Identifiable {
    let id = UUID()
    let slot: Int
    let config: PaneConfig

    @Published var output: String = ""
    @Published var state: PaneState = .idle

    private let outputLimit = 300_000
    private var runner: PTYProcess?

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
        guard state.isRunning else { return }
        runner?.write(text)
    }

    func interrupt() {
        guard state.isRunning else { return }
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
    }

    private func append(_ text: String) {
        output += text
        if output.count > outputLimit {
            output.removeFirst(output.count - outputLimit)
        }
    }
}
