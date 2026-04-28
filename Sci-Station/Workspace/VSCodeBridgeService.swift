import Foundation

public enum PythonRuntimeMode: String, CaseIterable, Sendable, Hashable {
    case system
    case workspaceVenv
    case selectedVenv

    public nonisolated var label: String {
        switch self {
        case .system:
            return "System Python"
        case .workspaceVenv:
            return "Workspace .venv"
        case .selectedVenv:
            return "Selected venv"
        }
    }

    public nonisolated func pythonCommand(in workspace: ResearchWorkspace, selectedPythonPath: String? = nil) -> String {
        switch self {
        case .system:
            return "python3"
        case .workspaceVenv:
            return workspace.fileURL(for: ".venv/bin/python").path
        case .selectedVenv:
            return selectedPythonPath ?? "python3"
        }
    }
}

public actor VSCodeBridgeService {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func preparePythonRunTask(
        for material: WorkspaceMaterial,
        in workspace: ResearchWorkspace,
        runtimeMode: PythonRuntimeMode,
        selectedPythonPath: String? = nil
    ) throws {
        let vscodeDirectoryURL = workspace.directoryURL(for: ".vscode")
        try fileManager.createDirectory(at: vscodeDirectoryURL, withIntermediateDirectories: true)
        try pythonTasksJSON(
            relativePath: material.relativePath,
            pythonCommand: runtimeMode.pythonCommand(in: workspace, selectedPythonPath: selectedPythonPath)
        ).write(
            to: vscodeDirectoryURL.appendingPathComponent("tasks.json"),
            atomically: true,
            encoding: .utf8
        )

        let bridgeDirectoryURL = workspace.directoryURL(for: ".sci-station/vscode")
        try fileManager.createDirectory(at: bridgeDirectoryURL, withIntermediateDirectories: true)
        try lastRunJSON(
            relativePath: material.relativePath,
            runtimeMode: runtimeMode,
            pythonCommand: runtimeMode.pythonCommand(in: workspace, selectedPythonPath: selectedPythonPath)
        ).write(
            to: bridgeDirectoryURL.appendingPathComponent("last_python_run.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    private nonisolated func pythonTasksJSON(relativePath: String, pythonCommand: String) -> String {
        """
        {
          "version": "2.0.0",
          "tasks": [
            {
              "label": "Sci-Station: Run Python Material",
              "type": "shell",
              "command": "\(jsonEscaped(pythonCommand))",
              "args": ["\(jsonEscaped(relativePath))"],
              "group": {
                "kind": "build",
                "isDefault": true
              },
              "presentation": {
                "reveal": "always",
                "panel": "dedicated",
                "clear": true
              },
              "problemMatcher": []
            }
          ]
        }
        """
    }

        private nonisolated func lastRunJSON(relativePath: String, runtimeMode: PythonRuntimeMode, pythonCommand: String) -> String {
        """
        {
          "kind": "python-run",
          "relative_path": "\(jsonEscaped(relativePath))",
          "runtime_mode": "\(runtimeMode.rawValue)",
                    "python_command": "\(jsonEscaped(pythonCommand))",
          "task_label": "Sci-Station: Run Python Material"
        }
        """
    }

    private nonisolated func jsonEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
