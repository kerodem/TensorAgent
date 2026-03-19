import SwiftUI

@main
struct MultiLLMTerminalApp: App {
    var body: some Scene {
        WindowGroup {
            LaunchGateView()
        }
        .defaultSize(width: 1540, height: 960)
        .windowResizability(.contentMinSize)
    }
}
