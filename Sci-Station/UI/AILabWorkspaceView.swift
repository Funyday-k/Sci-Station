import SwiftUI

struct AILabWorkspaceView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AI Lab")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                    Text("Global AI workspace for LLM settings, paper summaries, Copilot Bridge exports, and future agent runs.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], alignment: .leading, spacing: 12) {
                    AILabMetricCard(title: "Provider", value: appModel.llmConfiguration.provider.rawValue, systemImage: "network")
                    AILabMetricCard(title: "Model", value: appModel.llmConfiguration.model, systemImage: "cpu")
                    AILabMetricCard(title: "Projects", value: "\(appModel.activeResearchProjects.count)", systemImage: "folder")
                    AILabMetricCard(title: "Papers", value: "\(appModel.papers.count)", systemImage: "books.vertical")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("DeepSeek")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Sci-Station uses the OpenAI-compatible endpoint by default. Configure the API key in Settings, then use paper Inspector actions such as Summarize with LLM.")
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button("Use DeepSeek Flash") {
                                appModel.useDeepSeekDefaults(model: "deepseek-v4-flash")
                                appModel.selectSection(.settings)
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Use DeepSeek Pro") {
                                appModel.useDeepSeekDefaults(model: "deepseek-v4-pro")
                                appModel.selectSection(.settings)
                            }
                            .buttonStyle(.bordered)

                            Button("Open Settings") {
                                appModel.selectSection(.settings)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Agent Workspace")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Agent runs and Copilot Bridge files are stored globally under .sci-station/agent so they can work across projects without mixing project data.")
                            .foregroundStyle(.secondary)

                        WorkspacePathRow(label: "Run Log", value: workspace.fileURL(for: ".sci-station/agent/runs.jsonl").path)
                        WorkspacePathRow(label: "Copilot Bridge", value: workspace.directoryURL(for: ".sci-station/agent/copilot-bridge").path)
                        WorkspacePathRow(label: "Current Project", value: appModel.currentResearchProject?.name ?? "None")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AILabMetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(value)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(title)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
