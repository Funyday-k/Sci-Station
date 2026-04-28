import Foundation

public actor WorkspaceMaterialRepository {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func loadMaterials(in workspace: ResearchWorkspace) throws -> [WorkspaceMaterial] {
        var materials: [WorkspaceMaterial] = []

        for relativePath in ResearchWorkspace.userMaterialRootPaths {
            let rootURL = workspace.directoryURL(for: relativePath)
            materials.append(contentsOf: try loadMaterialsUnderDirectory(rootURL, in: workspace))
        }

        for relativePath in ResearchWorkspace.userMaterialFilePaths {
            let fileURL = workspace.fileURL(for: relativePath)
            guard fileManager.fileExists(atPath: fileURL.path), Self.isVisibleMaterialPath(relativePath) else {
                continue
            }
            materials.append(try material(for: fileURL, relativePath: relativePath))
        }

        return materials.sorted { lhs, rhs in
            lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
        }
    }

    public nonisolated static func isVisibleMaterialPath(_ relativePath: String) -> Bool {
        let components = relativePath.split(separator: "/").map(String.init)
        guard let firstComponent = components.first else {
            return false
        }

        if components.contains(where: { $0.hasPrefix(".") }) {
            return false
        }

        if ResearchWorkspace.systemRootPaths.contains(firstComponent) {
            return false
        }

        return ResearchWorkspace.userMaterialRootPaths.contains(firstComponent)
            || ResearchWorkspace.userMaterialFilePaths.contains(relativePath)
    }

    private func loadMaterialsUnderDirectory(_ rootURL: URL, in workspace: ResearchWorkspace) throws -> [WorkspaceMaterial] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }

        let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        var materials: [WorkspaceMaterial] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            let relativePath = workspace.relativePath(to: fileURL)
            guard Self.isVisibleMaterialPath(relativePath) else {
                continue
            }

            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else {
                continue
            }

            materials.append(try material(for: fileURL, relativePath: relativePath))
        }

        return materials
    }

    private func material(for fileURL: URL, relativePath: String) throws -> WorkspaceMaterial {
        let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return WorkspaceMaterial(
            relativePath: relativePath,
            fileURL: fileURL,
            kind: kind(for: fileURL),
            byteCount: Int64(resourceValues.fileSize ?? 0),
            modifiedAt: resourceValues.contentModificationDate
        )
    }

    private nonisolated func kind(for fileURL: URL) -> WorkspaceMaterialKind {
        let fileExtension = fileURL.pathExtension.lowercased()

        if ["md", "markdown"].contains(fileExtension) {
            return .markdown
        }

        if ["png", "jpg", "jpeg", "gif", "webp", "tiff", "tif", "heic"].contains(fileExtension) {
            return .image
        }

        if fileExtension == "pdf" {
            return .pdf
        }

        if fileExtension == "py" {
            return .python
        }

        if [
            "txt", "csv", "tsv", "json", "yaml", "yml", "toml", "xml", "html", "css",
            "js", "ts", "jsx", "tsx", "swift", "c", "cc", "cpp", "h", "hpp",
            "m", "mm", "sh", "zsh", "bash", "r", "jl", "ipynb", "bib", "tex", "log"
        ].contains(fileExtension) {
            return .text
        }

        if ["npy", "npz", "h5", "hdf5", "parquet", "feather", "sqlite", "db"].contains(fileExtension) {
            return .data
        }

        return .other
    }
}
