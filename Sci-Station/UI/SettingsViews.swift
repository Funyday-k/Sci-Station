import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                    Text("Configure the OpenAI-compatible provider used for paper summaries.")
                        .foregroundStyle(.secondary)
                }

                GroupBox("LLM") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField(
                            "Base URL",
                            text: llmBinding(
                                get: { $0.baseURLString },
                                set: { configuration, newValue in
                                    configuration.baseURLString = newValue
                                }
                            )
                        )
                            .textFieldStyle(.roundedBorder)

                        TextField(
                            "Model",
                            text: llmBinding(
                                get: { $0.model },
                                set: { configuration, newValue in
                                    configuration.model = newValue
                                }
                            )
                        )
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 12) {
                            TextField(
                                "Temperature",
                                value: llmBinding(
                                    get: { $0.temperature },
                                    set: { configuration, newValue in
                                        configuration.temperature = newValue
                                    }
                                ),
                                format: .number
                            )
                                .textFieldStyle(.roundedBorder)
                            TextField("Max Tokens", value: Binding(
                                get: { appModel.llmConfiguration.maxTokens ?? 0 },
                                set: { newValue in
                                    appModel.updateLLMConfiguration { configuration in
                                        configuration.maxTokens = newValue == 0 ? nil : newValue
                                    }
                                }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                        }

                        SecureField("API Key", text: $appModel.llmAPIKey)
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 12) {
                            Button("Save Settings", action: appModel.saveLLMSettings)
                                .buttonStyle(.borderedProminent)
                            Button("Test Connection", action: appModel.testLLMConnection)
                                .buttonStyle(.bordered)
                        }

                        if appModel.isTestingLLMConnection {
                            ProgressView("Testing connection…")
                        }

                        if let message = appModel.llmConnectionStatusMessage {
                            Text(message)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Workspace") {
                    WorkspacePathRow(label: "Root", value: workspace.rootURL.path)
                    WorkspacePathRow(label: "Settings File", value: workspace.fileURL(for: "settings.yaml").path)
                }
            }
            .padding(24)
        }
    }

    private func llmBinding<Value>(
        get: @escaping (LLMConfiguration) -> Value,
        set: @escaping (inout LLMConfiguration, Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: { get(appModel.llmConfiguration) },
            set: { newValue in
                appModel.updateLLMConfiguration { configuration in
                    set(&configuration, newValue)
                }
            }
        )
    }
}

struct LLMSummaryPreviewView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("LLM Summary Preview")
                .font(.title2)
                .fontWeight(.semibold)

            TextEditor(text: Binding(
                get: { appModel.summaryPreviewText ?? "" },
                set: appModel.updateSummaryPreviewText
            ))
            .font(.system(.body, design: .monospaced))

            HStack(spacing: 12) {
                Button("Replace Wiki") {
                    appModel.applySummaryPreview(mode: .replace)
                }
                .buttonStyle(.borderedProminent)

                Button("Append") {
                    appModel.applySummaryPreview(mode: .append)
                }
                .buttonStyle(.bordered)

                Button("Save Draft") {
                    appModel.applySummaryPreview(mode: .saveDraft)
                }
                .buttonStyle(.bordered)

                Button("Close") {
                    dismiss()
                }
            }
        }
        .padding(20)
        .frame(minWidth: 860, minHeight: 560)
    }
}