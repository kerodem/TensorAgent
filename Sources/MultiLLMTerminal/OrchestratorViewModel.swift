import Foundation

@MainActor
final class OrchestratorViewModel: ObservableObject {
    @Published var providers: [LLMProvider] = []
    @Published var panes: [PaneSession] = []
    @Published var cwdInput: String = FileManager.default.currentDirectoryPath
    @Published var skipSafetyChecks: Bool = false
    @Published var allowUnsafeShellCommands: Bool = false
    @Published var autoLaunchOnStart: Bool = false
    @Published var errorMessage: String?

    private var didInitialLaunch = false

    init() {
        reloadProviders()
        rebuildPanesIfNeeded()
        applyDefaultProviders()
    }

    var providersPath: String {
        ProviderStore.providersPathForDisplay()
    }

    var orchestratorStatline: String {
        let totalSlots = panes.count
        let enabled = panes.filter { $0.config.enabled }.count
        let active = panes.filter {
            if case .launching = $0.state { return true }
            if case .running = $0.state { return true }
            return false
        }.count
        let running = panes.filter { $0.state.isRunning }
        let runningNames = running.compactMap { pane -> String? in
            guard let provider = providerByID(pane.config.providerID) else { return nil }
            return provider.name
        }

        let uniqueNames = Array(Set(runningNames)).sorted()
        let runningLabel = uniqueNames.isEmpty ? "none" : uniqueNames.joined(separator: ", ")

        return "\(enabled) models enabled | \(totalSlots) parallel PTY slots | \(active) active PTY sessions | Running: \(runningLabel)"
    }

    func startIfNeeded() {
        guard !didInitialLaunch else { return }
        didInitialLaunch = true

        if autoLaunchOnStart {
            launchGrid(authOnly: false)
        }
    }

    func applySettingsAndRelaunch() {
        if autoLaunchOnStart {
            launchGrid(authOnly: false)
        }
    }

    func reloadProviders() {
        providers = ProviderStore.loadProviders().sorted { $0.name < $1.name }
    }

    func providerByID(_ id: String) -> LLMProvider? {
        providers.first { $0.id == id }
    }

    func paneTitle(_ pane: PaneSession) -> String {
        let custom = pane.config.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            return custom
        }

        if let provider = providerByID(pane.config.providerID) {
            return provider.name
        }

        return "Window \(pane.slot + 1)"
    }

    func paneProviderName(_ pane: PaneSession) -> String {
        if let provider = providerByID(pane.config.providerID) {
            return provider.name
        }
        return "Unassigned"
    }

    func launchAuthGrid() {
        launchGrid(authOnly: true)
    }

    func stopAll() {
        for pane in panes {
            pane.stop()
        }
    }

    private func launchGrid(authOnly: Bool) {
        for pane in panes where pane.config.enabled {
            launchSinglePane(pane, authOnly: authOnly)
        }

        for pane in panes where !pane.config.enabled {
            pane.stop()
            pane.clear()
            pane.state = .idle
        }
    }

    private func launchSinglePane(_ pane: PaneSession, authOnly: Bool) {
        guard let provider = providerByID(pane.config.providerID) else {
            pane.clear()
            pane.launch(command: "printf '[error] invalid provider selection\\n'; exec zsh -l", cwd: resolvedCWD())
            return
        }

        do {
            if !skipSafetyChecks {
                try ensureBinary(for: provider)
            }

            let command = try renderCommand(provider: provider, config: pane.config, authOnly: authOnly)
            pane.launch(command: command, cwd: resolvedCWD())
        } catch {
            pane.clear()
            let escaped = shellQuote("[error] \(error.localizedDescription)\n")
            pane.launch(command: "printf %s \(escaped); exec zsh -l", cwd: resolvedCWD())
        }
    }

    private func renderCommand(provider: LLMProvider, config: PaneConfig, authOnly: Bool) throws -> String {
        if authOnly {
            let auth = provider.authCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if auth.isEmpty {
                throw NSError(
                    domain: "Orchestrator",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Provider '\(provider.id)' has no auth command"]
                )
            }
            try validateSafeShellFragment(auth, context: "auth command for provider '\(provider.id)'")
            return auth
        }

        let extra = config.extraArgs.trimmingCharacters(in: .whitespacesAndNewlines)
        let custom = config.customCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            if !allowUnsafeShellCommands {
                throw NSError(
                    domain: "Orchestrator",
                    code: 6,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Custom commands are disabled by default. Enable 'Allow unsafe shell commands' in Settings to run them."
                    ]
                )
            }

            return [custom, extra]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }

        var command = provider.commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = config.modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedModel = model.isEmpty ? provider.defaultModel : model

        if command.contains("{model}") {
            if selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw NSError(
                    domain: "Orchestrator",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Provider '\(provider.id)' requires a model value"]
                )
            }
            command = command.replacingOccurrences(of: "{model}", with: shellQuote(selectedModel))
        }

        if !extra.isEmpty {
            try validateSafeShellFragment(extra, context: "extra args")
            command += " \(extra)"
        }

        if command.isEmpty {
            throw NSError(
                domain: "Orchestrator",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Resolved command is empty for provider '\(provider.id)'"
                ]
            )
        }

        try validateSafeShellFragment(command, context: "resolved command for provider '\(provider.id)'")
        return command
    }

    private func ensureBinary(for provider: LLMProvider) throws {
        let binary = resolvedBinary(provider)
        if binary.isEmpty { return }

        if binary.contains("/") {
            let expanded = NSString(string: binary).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return
            }
            throw NSError(
                domain: "Orchestrator",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Binary not executable: \(expanded)"]
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [binary]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw NSError(
                domain: "Orchestrator",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "CLI '\(binary)' not found in PATH"]
            )
        }
    }

    private func resolvedBinary(_ provider: LLMProvider) -> String {
        if let binary = provider.binary?.trimmingCharacters(in: .whitespacesAndNewlines), !binary.isEmpty {
            return binary
        }

        return provider.commandTemplate
            .split(separator: " ")
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func resolvedCWD() -> String {
        let input = cwdInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isEmpty {
            return FileManager.default.currentDirectoryPath
        }

        let expanded = NSString(string: input).expandingTildeInPath
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
            return URL(fileURLWithPath: expanded).standardized.path
        }

        errorMessage = "Invalid working directory: \(expanded)"
        return FileManager.default.currentDirectoryPath
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func validateSafeShellFragment(_ value: String, context: String) throws {
        if allowUnsafeShellCommands {
            return
        }

        if containsUnsafeShellSyntax(value) {
            throw NSError(
                domain: "Orchestrator",
                code: 7,
                userInfo: [
                    NSLocalizedDescriptionKey: "\(context) contains blocked shell metacharacters. Enable 'Allow unsafe shell commands' in Settings only if you trust this command."
                ]
            )
        }
    }

    private func containsUnsafeShellSyntax(_ value: String) -> Bool {
        let blockedMarkers = [";", "|", "&", "`", "$(", ">", "<", "\n", "\r"]
        return blockedMarkers.contains { value.contains($0) }
    }

    func rebuildPanesIfNeeded() {
        if panes.count == 6 { return }

        panes = (0..<6).map { slot in
            let config = PaneConfig(
                slot: slot,
                enabled: true,
                title: "Window \(slot + 1)",
                providerID: "",
                modelOverride: "",
                extraArgs: "",
                customCommand: ""
            )
            return PaneSession(slot: slot, config: config)
        }
    }

    func applyDefaultProviders() {
        let defaults = ["claude", "codex", "gemini", "ollama", "lmstudio", "custom-local"]
        for (index, pane) in panes.enumerated() {
            if index < defaults.count {
                pane.config.providerID = defaults[index]
                pane.config.enabled = index < 6
            }
        }
    }
}
