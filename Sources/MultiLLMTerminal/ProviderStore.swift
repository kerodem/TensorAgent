import Foundation

enum ProviderStore {
    static func loadProviders() -> [LLMProvider] {
        let paths = candidatePaths()
        for path in paths {
            guard FileManager.default.fileExists(atPath: path.path) else { continue }
            do {
                let data = try Data(contentsOf: path)
                let providers = try JSONDecoder().decode([LLMProvider].self, from: data)
                if !providers.isEmpty {
                    return providers
                }
            } catch {
                continue
            }
        }

        return fallbackProviders
    }

    static func providersPathForDisplay() -> String {
        candidatePaths().first?.path ?? ""
    }

    private static func candidatePaths() -> [URL] {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MultiLLMTerminal", isDirectory: true)
            .appendingPathComponent("providers.json")

        let repo = URL(fileURLWithPath: fm.currentDirectoryPath)
            .appendingPathComponent("providers.json")

        return [appSupport, repo]
    }

    private static let fallbackProviders: [LLMProvider] = [
        .init(
            id: "claude",
            name: "Claude CLI",
            description: "Anthropic Claude CLI",
            commandTemplate: "claude",
            defaultModel: "",
            binary: "claude",
            authCommand: "claude auth login",
            authNotes: "Authenticate once before running sessions"
        ),
        .init(
            id: "codex",
            name: "Codex CLI",
            description: "OpenAI Codex CLI",
            commandTemplate: "codex",
            defaultModel: "",
            binary: "codex",
            authCommand: "codex login",
            authNotes: "Authenticate once before running sessions"
        ),
        .init(
            id: "gemini",
            name: "Gemini CLI",
            description: "Google Gemini CLI",
            commandTemplate: "gemini",
            defaultModel: "",
            binary: "gemini",
            authCommand: "gemini auth login",
            authNotes: "Authenticate once before running sessions"
        ),
        .init(
            id: "ollama",
            name: "Ollama",
            description: "Local runtime via Ollama",
            commandTemplate: "ollama run {model}",
            defaultModel: "llama3.2",
            binary: "ollama",
            authCommand: nil,
            authNotes: "No cloud auth required"
        ),
        .init(
            id: "lmstudio",
            name: "LM Studio",
            description: "Local runtime via LM Studio",
            commandTemplate: "lms chat {model}",
            defaultModel: "local-model",
            binary: "lms",
            authCommand: nil,
            authNotes: "No cloud auth required"
        ),
        .init(
            id: "custom-local",
            name: "Custom Local",
            description: "Custom local/runtime command",
            commandTemplate: "echo 'Set custom command'",
            defaultModel: "",
            binary: nil,
            authCommand: nil,
            authNotes: nil
        )
    ]
}
