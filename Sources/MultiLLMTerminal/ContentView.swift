import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = OrchestratorViewModel()
    @State private var showSettings = false

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            grid
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 1500, minHeight: 920)
        .onAppear {
            viewModel.startIfNeeded()
        }
        .sheet(isPresented: $showSettings, onDismiss: {
            viewModel.applySettingsAndRelaunch()
        }) {
            SettingsSheet(viewModel: viewModel)
        }
        .alert("Launch Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Text(viewModel.orchestratorStatline)
                .font(.custom("Menlo", size: 12))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .help("Settings")
        }
        .padding(10)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(viewModel.panes) { pane in
                PaneCard(
                    pane: pane,
                    title: viewModel.paneTitle(pane),
                    providerName: viewModel.paneProviderName(pane)
                )
            }
        }
        .padding(10)
        .background(Color.black)
    }
}

private struct PaneCard: View {
    @ObservedObject var pane: PaneSession
    let title: String
    let providerName: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.custom("Menlo", size: 12))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Text(providerName)
                    .font(.custom("Menlo", size: 11))
                    .foregroundStyle(.secondary)

                Text("| \(pane.state.label)")
                    .font(.custom("Menlo", size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            TerminalSurfaceView(output: pane.output) { input in
                pane.sendInput(input)
            }
            .frame(minHeight: 360)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct SettingsSheet: View {
    @ObservedObject var viewModel: OrchestratorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Orchestrator Settings")
                    .font(.title3.bold())

                GroupBox("Global") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Working directory", text: $viewModel.cwdInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.custom("Menlo", size: 12))

                        Toggle("Skip safety checks", isOn: $viewModel.skipSafetyChecks)
                        Toggle("Allow unsafe shell commands", isOn: $viewModel.allowUnsafeShellCommands)
                        Toggle("Auto launch on open/close settings", isOn: $viewModel.autoLaunchOnStart)

                        Text(viewModel.providersPath)
                            .font(.custom("Menlo", size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                }

                GroupBox("Pane Configuration") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.panes) { pane in
                            PaneSettingsRow(pane: pane, config: pane.config, providers: viewModel.providers)
                                .padding(8)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(8)
                }

                Text("Close this settings window to apply and relaunch the orchestration grid.")
                    .font(.custom("Menlo", size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
        }
        .frame(minWidth: 1000, minHeight: 760)
    }
}

private struct PaneSettingsRow: View {
    @ObservedObject var pane: PaneSession
    @ObservedObject var config: PaneConfig
    let providers: [LLMProvider]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle("Enabled", isOn: $config.enabled)
                    .toggleStyle(.switch)
                    .frame(width: 110)

                Text("Pane \(pane.slot + 1)")
                    .font(.custom("Menlo", size: 12))

                TextField("Title", text: $config.title)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                Picker("Provider", selection: $config.providerID) {
                    ForEach(providers) { provider in
                        Text(provider.name).tag(provider.id)
                    }
                }
                .pickerStyle(.menu)

                TextField("Model", text: $config.modelOverride)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)

                TextField("Extra args", text: $config.extraArgs)
                    .textFieldStyle(.roundedBorder)

                TextField("Custom command", text: $config.customCommand)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}
