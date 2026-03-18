import Foundation

struct LLMProvider: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let description: String
    let commandTemplate: String
    let defaultModel: String
    let binary: String?
    let authCommand: String?
    let authNotes: String?
}

enum PaneState: Equatable {
    case idle
    case launching
    case running
    case exited(Int32)
    case failed(String)

    var label: String {
        switch self {
        case .idle:
            return "Idle"
        case .launching:
            return "Launching"
        case .running:
            return "Running"
        case let .exited(code):
            return "Exited (\(code))"
        case let .failed(message):
            return "Failed: \(message)"
        }
    }

    var isRunning: Bool {
        if case .running = self {
            return true
        }
        return false
    }
}

@MainActor
final class PaneConfig: ObservableObject, Identifiable {
    let id = UUID()
    let slot: Int

    @Published var enabled: Bool
    @Published var title: String
    @Published var providerID: String
    @Published var modelOverride: String
    @Published var extraArgs: String
    @Published var customCommand: String

    init(
        slot: Int,
        enabled: Bool,
        title: String,
        providerID: String,
        modelOverride: String = "",
        extraArgs: String = "",
        customCommand: String = ""
    ) {
        self.slot = slot
        self.enabled = enabled
        self.title = title
        self.providerID = providerID
        self.modelOverride = modelOverride
        self.extraArgs = extraArgs
        self.customCommand = customCommand
    }
}
