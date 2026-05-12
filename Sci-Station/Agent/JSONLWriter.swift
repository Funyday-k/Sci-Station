import Foundation

/// Actor-backed writer for JSONL (newline-delimited JSON) files.
///
/// - Each append opens the file, seeks to end, writes the new row, calls
///   `synchronize()` to flush OS buffers to disk, then closes. We deliberately
///   do not hold the file handle across calls because tests and other tools
///   can legitimately replace the file via atomic rename; keeping a stale
///   handle would then write to an orphaned inode.
/// - An optional in-memory `seenIDs` cache makes deduplication O(1) rather
///   than re-scanning the whole file on every append (which was O(N²) in the
///   previous implementation inside `AgentRunDirectoryStore.appendEvent`).
///
/// Callers should share a single `JSONLWriter` instance per (url) target so
/// the actor serialises writes and the dedup cache stays warm.
/// `JSONLWriterRegistry` (below) provides a cached factory for this purpose.
public actor JSONLWriter {
    public let url: URL
    private let fileManager: FileManager
    private var seenIDs: Set<String> = []
    private var hasLoadedSeenIDs = false
    private let idExtractor: (@Sendable (Data) -> String?)?

    public init(
        url: URL,
        fileManager: FileManager = .default,
        idExtractor: (@Sendable (Data) -> String?)? = nil
    ) {
        self.url = url
        self.fileManager = fileManager
        self.idExtractor = idExtractor
    }

    /// Appends an encodable value. If `id` is non-nil and already present in
    /// the dedup cache, the append is skipped. Returns `true` when a new line
    /// was actually written.
    @discardableResult
    public func append<T: Encodable>(
        _ value: T,
        encoder: JSONEncoder = JSONLWriter.defaultEncoder(),
        id: String? = nil
    ) throws -> Bool {
        let data = try encoder.encode(value)
        return try appendRawData(data, id: id)
    }

    /// Appends raw JSON-encoded bytes (no trailing newline).
    @discardableResult
    public func appendRawData(_ data: Data, id: String? = nil) throws -> Bool {
        if let id {
            try ensureSeenIDsLoaded()
            if seenIDs.contains(id) {
                return false
            }
        }

        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var payload = data
        payload.append(0x0a)

        if fileManager.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
            try handle.synchronize()
        } else {
            try payload.write(to: url, options: .atomic)
        }

        if let id {
            seenIDs.insert(id)
        }
        return true
    }

    /// Forces the dedup cache to be rehydrated from disk on the next append.
    public func invalidateCache() {
        seenIDs = []
        hasLoadedSeenIDs = false
    }

    private func ensureSeenIDsLoaded() throws {
        if hasLoadedSeenIDs { return }
        hasLoadedSeenIDs = true
        guard fileManager.fileExists(atPath: url.path),
              let idExtractor else {
            return
        }
        let data = try Data(contentsOf: url)
        var start = data.startIndex
        while start < data.endIndex {
            if let end = data[start..<data.endIndex].firstIndex(of: 0x0a) {
                let slice = data[start..<end]
                if let id = idExtractor(Data(slice)) {
                    seenIDs.insert(id)
                }
                start = data.index(after: end)
            } else {
                let slice = data[start..<data.endIndex]
                if let id = idExtractor(Data(slice)) {
                    seenIDs.insert(id)
                }
                break
            }
        }
    }

    public nonisolated static func defaultEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

/// Process-wide registry that hands out shared `JSONLWriter` actors keyed by
/// canonical file path. This matters because `AgentRunLogger`,
/// `AgentSessionEventLogger`, `AppDebugEventLogger`, and
/// `AgentRunDirectoryStore` may all be instantiated independently but must
/// coordinate writes to the same files.
public actor JSONLWriterRegistry {
    public static let shared = JSONLWriterRegistry()

    private var writers: [String: JSONLWriter] = [:]

    public init() {}

    public func writer(
        for url: URL,
        idExtractor: (@Sendable (Data) -> String?)? = nil
    ) -> JSONLWriter {
        let key = url.standardizedFileURL.path
        if let cached = writers[key] {
            return cached
        }
        let writer = JSONLWriter(url: url, idExtractor: idExtractor)
        writers[key] = writer
        return writer
    }
}
