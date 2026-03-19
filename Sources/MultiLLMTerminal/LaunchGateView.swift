import SwiftUI

struct LaunchGateView: View {
    @State private var ready = false

    var body: some View {
        Group {
            if ready {
                ContentView()
            } else {
                SplashView()
                    .task {
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        ready = true
                    }
            }
        }
    }
}

private struct SplashView: View {
    private let logo = """
    ||
    ||\\
    || \\
    ||  \\
    ||  /
    || /
    ||/
    """

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text(logo)
                    .font(.custom("Menlo", size: 28))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)

                Text("tensoragent0.0.1pa")
                    .font(.custom("Menlo", size: 13))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
        }
    }
}
