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
        ".sci-station",
        "refs",
        "refs/csl",
        "settings",
        "tasks",
        "imports",
        "data",
        "prompts",
        "scripts",
        "code",
        "figures",
        "outputs",
        ".sci-station/agent"
    ]

    public nonisolated static let userMaterialRootPaths: [String] = [
        "inbox",
        "data",
        "code",
        "figures",
        "outputs",
        "scripts",
        "prompts"
    ]

    public nonisolated static let userMaterialFilePaths: [String] = [
        "shared_research.md"
    ]

    public nonisolated static let systemRootPaths: Set<String> = [
        ".sci-station",
        "settings",
        "refs",
        "tasks",
        "imports"
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
            relativePath: "settings/workspace_preferences.yaml",
            contents: "schema_version: 1\nlibrary_visible_columns:\n  - \"title\"\n  - \"authors\"\n  - \"year\"\n  - \"tags\"\n  - \"projects\"\n  - \"collection\"\nlibrary_sort_field: \"\"\nlibrary_sort_ascending: true\ndefault_collection: \"\"\nrecent_section: \"projects\"\nsync_todos_to_apple_reminders: true\napp_language: \"system\"\nagent_chat_font_size: 14.0\nmineru_command: \"mineru\"\nmineru_api_base_url: \"https://mineru.net\"\nmineru_api_language: \"en\"\nmineru_overwrite_existing_markdown: true\n"
        ),
        SeededFile(
            relativePath: "settings/markdown_snippets.yaml",
            contents: "snippets:\n  - trigger: \";h2\"\n    title: \"Heading 2\"\n    body: |\n      ## ${cursor}\n  - trigger: \";eq\"\n    title: \"Display Equation\"\n    body: |\n      $$\n      ${cursor}\n      $$\n  - trigger: \";fig\"\n    title: \"Figure Reference\"\n    body: |\n      ![${cursor}](../figures/)\n  - trigger: \";todo\"\n    title: \"Todo Item\"\n    body: |\n      - [ ] ${cursor}\n  - trigger: \";paper\"\n    title: \"Paper Note\"\n    body: |\n      ## Why It Matters\n      \n      ${cursor}\n      \n      ## Method\n      \n      \n      ## Limits\n"
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
            relativePath: "wiki/projects/project_overview.md",
            contents: "# Project Overview\n\nUse this page as the living proposal for the current research project. Record the research question, scope, expected contribution, core papers, datasets, code reading notes, figures, outputs, and next milestones here.\n\n## Research Question\n\n\n## Project Thesis\n\n\n## Core Papers\n\n- Add foundational papers and short notes here.\n\n## Data\n\n- Store datasets or dataset notes under `data/` and `wiki/datasets/`.\n\n## Code Reading\n\n- Store scripts, code snippets, and reading notes under `code/`.\n\n## Figures And Outputs\n\n- Store figures under `figures/` and generated outputs under `outputs/`.\n"
        ),
        SeededFile(
            relativePath: "wiki/projects/core_papers.md",
            contents: "# Core Papers\n\nMaintain the project-level reading canon here. For each core paper, record why it matters, what method or result it contributes, and how it affects the project proposal.\n\n## Papers\n\n- `citekey`: short contribution note.\n"
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

    public nonisolated var globalPapersURL: URL {
        directoryURL(for: "library/papers")
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

    public nonisolated var dataURL: URL {
        directoryURL(for: "data")
    }

    public nonisolated var promptsURL: URL {
        directoryURL(for: "prompts")
    }

    public nonisolated var codeURL: URL {
        directoryURL(for: "code")
    }

    public nonisolated var figuresURL: URL {
        directoryURL(for: "figures")
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

    public nonisolated var globalLibraryBibURL: URL {
        fileURL(for: "library/refs/library.bib")
    }

    public nonisolated var projectPaperLinksURL: URL {
        fileURL(for: "library/project_paper_links.yaml")
    }

    public nonisolated var tagsDefinitionURL: URL {
        fileURL(for: "refs/tags.yaml")
    }

    public nonisolated var workspacePreferencesURL: URL {
        fileURL(for: "settings/workspace_preferences.yaml")
    }

    public nonisolated var markdownSnippetsURL: URL {
        fileURL(for: "settings/markdown_snippets.yaml")
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
            ("Papers", globalPapersURL),
            ("Wiki Papers", wikiPapersURL),
            ("References", refsURL),
            ("Tasks", tasksURL),
            ("Imports", importsURL),
            ("Data", dataURL),
            ("Prompts", promptsURL),
            ("Code", codeURL),
            ("Figures", figuresURL),
            ("Outputs", outputsURL)
        ]
    }

}