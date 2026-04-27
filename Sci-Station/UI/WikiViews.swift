import SwiftUI

struct WikiWorkspaceView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wiki")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                    Text("Browse and edit Markdown knowledge pages under wiki/. Backlinks update whenever you save changes.")
                        .foregroundStyle(.secondary)
                }

                Text("\(appModel.markdownDocuments.count) pages in \(workspace.displayName)")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                MarkdownPageListView()
            }
            .padding(20)
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 360, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            MarkdownEditorView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if appModel.markdownDocuments.isEmpty {
                appModel.reloadWiki()
            }
        }
    }
}

struct WikiInspectorView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    var body: some View {
        ScrollView {
            if let document = appModel.selectedMarkdownDraft {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Wiki Inspector")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text(document.title)
                            .foregroundStyle(.secondary)
                    }

                    GroupBox("File") {
                        VStack(alignment: .leading, spacing: 10) {
                            WorkspacePathRow(label: "Page", value: document.relativePath)
                            WorkspacePathRow(label: "Category", value: document.category)
                            WorkspacePathRow(label: "Workspace Root", value: workspace.rootURL.path)
                        }
                        .padding(.vertical, 4)
                    }

                    GroupBox("Frontmatter") {
                        VStack(alignment: .leading, spacing: 8) {
                            if document.frontmatterEntries.isEmpty {
                                Text("No frontmatter found.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(document.frontmatterEntries) { entry in
                                    WorkspacePathRow(label: entry.key, value: entry.value)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    GroupBox("Outgoing Links") {
                        VStack(alignment: .leading, spacing: 8) {
                            if document.outgoingLinks.isEmpty {
                                Text("No wikilinks found in the saved document.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(document.outgoingLinks) { link in
                                    Text(link.target)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }

                    GroupBox("Backlinks") {
                        VStack(alignment: .leading, spacing: 8) {
                            if appModel.selectedMarkdownBacklinks.isEmpty {
                                Text("No backlinks yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(appModel.selectedMarkdownBacklinks) { reference in
                                    Button(reference.title) {
                                        appModel.openMarkdownDocument(relativePath: reference.relativePath)
                                    }
                                    .buttonStyle(.link)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }
                .padding(20)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Wiki Inspector")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Select a wiki page to inspect frontmatter, outgoing links, and backlinks.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
            }
        }
    }
}