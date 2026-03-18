import SwiftUI

@main
struct MultiLLMTerminalApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1540, height: 960)
        .windowResizability(.contentMinSize)
    }
}
