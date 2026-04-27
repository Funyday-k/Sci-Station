import Foundation

public struct ResearchWorkspace: Identifiable, Equatable, Sendable {
    public struct SeededFile: Sendable {
        public let relativePath: String
        public let contents: String
    }

    public nonisolated static let requiredDirectoryPaths: [String] = [
        "inbox",
        "raw/papers",
        "raw/web",
        "raw/books",
        "wiki/papers",
        "wiki/concepts",
        "wiki/methods",
        "wiki/datasets",
        "wiki/authors",
        "wiki/gaps",
        "wiki/projects",
        "refs",
        "refs/csl",
        "tasks",
        "imports",
        "prompts",
        "scripts",
        "code",
        "outputs"
    ]

    public nonisolated static let seededFiles: [SeededFile] = [
        SeededFile(
            relativePath: "shared_research.md",
            contents: "# Shared Research Context\n\nUse this file to keep the current research state, reusable prompts, and cross-paper findings that should be shared across LLM tasks.\n"
        ),
        SeededFile(
            relativePath: "refs/library.bib",
            contents: "% Sci-Station bibliography\n"
        ),
        SeededFile(
            relativePath: "refs/tags.yaml",
            contents: "tags: []\n"
        ),
        SeededFile(
            relativePath: "tasks/todos.yaml",
            contents: "todos: []\n"
        ),
        SeededFile(
            relativePath: "tasks/calendar.yaml",
            contents: "events: []\n"
        ),
        SeededFile(
            relativePath: "imports/import_history.yaml",
            contents: "imports: []\n"
        ),
        SeededFile(
            relativePath: "imports/failed_imports.yaml",
            contents: "failed_imports: []\n"
        ),
        SeededFile(
            relativePath: "researchflow.sqlite",
            contents: ""
        )
    ]

    public let rootURL: URL

    public nonisolated init(rootURL: URL) { self.rootURL = rootURL }

    public nonisolated var id: URL {
        rootURL
    }

    public nonisolated var displayName: String {
        rootURL.lastPathComponent
    }

    public nonisolated var inboxURL: URL {
        directoryURL(for: "inbox")
    }

    public nonisolated var rawPapersURL: URL {
        directoryURL(for: "raw/papers")
    }

    public nonisolated var wikiPapersURL: URL {
        directoryURL(for: "wiki/papers")
    }

    public nonisolated var refsURL: URL {
        directoryURL(for: "refs")
    }

    public nonisolated var tasksURL: URL {
        directoryURL(for: "tasks")
    }

    public nonisolated var importsURL: URL {
        directoryURL(for: "imports")
    }

    public nonisolated var promptsURL: URL {
        directoryURL(for: "prompts")
    }

    public nonisolated var codeURL: URL {
        directoryURL(for: "code")
    }

    public nonisolated var outputsURL: URL {
        directoryURL(for: "outputs")
    }

    public nonisolated var sharedResearchURL: URL {
        fileURL(for: "shared_research.md")
    }

    public nonisolated var libraryBibURL: URL {
        fileURL(for: "refs/library.bib")
    }

    public nonisolated var tagsDefinitionURL: URL {
        fileURL(for: "refs/tags.yaml")
    }

    public nonisolated var researchFlowDatabaseURL: URL {
        fileURL(for: "researchflow.sqlite")
    }

    public nonisolated func directoryURL(for relativePath: String) -> URL {
        resolve(relativePath: relativePath, from: rootURL, isDirectory: true)
    }

    public nonisolated func fileURL(for relativePath: String) -> URL {
        resolve(relativePath: relativePath, from: rootURL, isDirectory: false)
    }

    public nonisolated func resolve(relativePath: String, from baseURL: URL, isDirectory: Bool) -> URL {
        let components = relativePath.split(separator: "/")

        return components.enumerated().reduce(baseURL) { partialURL, component in
            let isLastComponent = component.offset == components.count - 1
            return partialURL.appendingPathComponent(
                String(component.element),
                isDirectory: isLastComponent ? isDirectory : true
            )
        }
    }

    public nonisolated func relativePath(to url: URL) -> String {
        let standardizedRoot = rootURL.standardizedFileURL.path
        let standardizedTarget = url.standardizedFileURL.path

        guard standardizedTarget.hasPrefix(standardizedRoot) else {
            return standardizedTarget
        }

        let trimmed = standardizedTarget.dropFirst(standardizedRoot.count)
        return trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : String(trimmed)
    }

    public nonisolated func missingRequiredItems(using fileManager: FileManager = .default) -> [String] {
        let missingDirectories = Self.requiredDirectoryPaths.filter {
            !fileManager.fileExists(atPath: directoryURL(for: $0).path)
        }
        let missingFiles = Self.seededFiles.map(\.relativePath).filter {
            !fileManager.fileExists(atPath: fileURL(for: $0).path)
        }

        return missingDirectories + missingFiles
    }

    public nonisolated var quickAccessLocations: [(name: String, url: URL)] {
        [
            ("Inbox", inboxURL),
            ("Papers", rawPapersURL),
            ("Wiki Papers", wikiPapersURL),
            ("References", refsURL),
            ("Tasks", tasksURL),
            ("Imports", importsURL),
            ("Prompts", promptsURL),
            ("Code", codeURL),
            ("Outputs", outputsURL)
        ]
    }

}