import Foundation
import PDFKit

public actor PaperSummaryService {
    private let provider: any LLMProvider
    private let promptBuilder: PaperSummaryPromptBuilder
    private let maximumPromptSourceCharacters = 60_000

    public init(provider: any LLMProvider, promptBuilder: PaperSummaryPromptBuilder = PaperSummaryPromptBuilder()) {
        self.provider = provider
        self.promptBuilder = promptBuilder
    }

    public func summarize(
        _ paper: Paper,
        in workspace: ResearchWorkspace,
        configuration: LLMConfiguration,
        apiKey: String
    ) async throws -> String {
        let rawMarkdown = rawMarkdownForPrompt(paper, in: workspace)
        let annotations = paper.annotationsRelativePath.flatMap { path in
            try? String(contentsOf: workspace.resolve(relativePath: path, from: workspace.directoryURL(for: paper.paperDirectoryRelativePath), isDirectory: false), encoding: .utf8)
        } ?? ""
        let existingWiki = paper.summaryURL(in: workspace).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        let prompt = promptBuilder.buildPrompt(for: paper, rawMarkdown: rawMarkdown, annotations: annotations, existingWiki: existingWiki)
        return try await provider.complete(prompt: prompt, configuration: configuration, apiKey: apiKey)
    }

    private func rawMarkdownForPrompt(_ paper: Paper, in workspace: ResearchWorkspace) -> String {
        let rawMarkdown = (try? String(contentsOf: paper.rawMarkdownURL(in: workspace), encoding: .utf8)) ?? ""
        guard shouldUsePDFTextFallback(rawMarkdown),
              let pdfURL = paper.pdfURL(in: workspace),
              let pdfText = extractedText(from: pdfURL),
              !pdfText.isEmpty else {
            return limited(rawMarkdown)
        }

        return limited(
            [
                rawMarkdown,
                "## Extracted PDF Text",
                pdfText
            ]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
        )
    }

    private nonisolated func shouldUsePDFTextFallback(_ rawMarkdown: String) -> Bool {
        let trimmedRawMarkdown = rawMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedRawMarkdown.count < 500
            || rawMarkdown.contains("status: not_extracted")
            || rawMarkdown.localizedCaseInsensitiveContains("PDF text has not been extracted yet")
    }

    private nonisolated func extractedText(from pdfURL: URL) -> String? {
        guard let document = PDFDocument(url: pdfURL) else {
            return nil
        }

        var pageTexts: [String] = []
        var collectedLength = 0

        for pageIndex in 0..<document.pageCount {
            guard let pageText = document.page(at: pageIndex)?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !pageText.isEmpty else {
                continue
            }

            pageTexts.append("### Page \(pageIndex + 1)\n\(pageText)")
            collectedLength += pageText.count

            if collectedLength >= maximumPromptSourceCharacters {
                break
            }
        }

        return pageTexts.joined(separator: "\n\n")
    }

    private nonisolated func limited(_ value: String) -> String {
        guard value.count > maximumPromptSourceCharacters else {
            return value
        }

        let endIndex = value.index(value.startIndex, offsetBy: maximumPromptSourceCharacters)
        return String(value[..<endIndex]) + "\n\n[Input truncated by Sci-Station.]"
    }
}

public struct PaperMarkdownConversionResult: Identifiable, Hashable, Sendable {
    public var id: String { paperID }
    public var paperID: String
    public var title: String
    public var markdownRelativePath: String?
    public var didWriteMarkdown: Bool
    public var errorMessage: String?
    public var extractionEngine: String? = nil
    public var fallbackReason: String? = nil
}

public nonisolated enum PaperMarkdownConversionState: String, Codable, Hashable, Sendable {
    case noPDF = "no_pdf"
    case notConverted = "not_converted"
    case converting
    case succeeded
    case fallback
    case failed
}

public nonisolated enum PaperMarkdownConversionError: LocalizedError, Sendable {
    case missingMinerUAPIToken
    case invalidMinerUAPIBaseURL(String)
    case minerUAPIError(String)
    case missingUploadURL
    case uploadFailed(Int)
    case resultFailed(String)
    case resultTimedOut
    case missingResultZipURL
    case badZipArchive
    case markdownNotFound

    public var errorDescription: String? {
        switch self {
        case .missingMinerUAPIToken:
            return "MinerU API token is missing."
        case let .invalidMinerUAPIBaseURL(value):
            return "Invalid MinerU API base URL: \(value)."
        case let .minerUAPIError(message):
            return "MinerU API error: \(message)"
        case .missingUploadURL:
            return "MinerU API did not return an upload URL."
        case let .uploadFailed(statusCode):
            return "MinerU upload failed with HTTP \(statusCode)."
        case let .resultFailed(message):
            return "MinerU extraction failed: \(message)"
        case .resultTimedOut:
            return "MinerU extraction timed out."
        case .missingResultZipURL:
            return "MinerU result did not include a Markdown zip URL."
        case .badZipArchive:
            return "MinerU result zip could not be extracted."
        case .markdownNotFound:
            return "MinerU result zip did not contain a Markdown file."
        }
    }
}

public struct PaperMarkdownConversionConfiguration: Hashable, Sendable {
    public var minerUAPIToken: String
    public var minerUAPIBaseURLString: String
    public var minerUModelVersion: String
    public var minerUAPILanguage: String
    public var minerUCommand: String
    public var overwriteExistingMarkdown: Bool
    public var pollIntervalSeconds: UInt64
    public var pollTimeoutSeconds: TimeInterval

    public nonisolated init(
        minerUAPIToken: String = "",
        minerUAPIBaseURLString: String = "https://mineru.net",
        minerUModelVersion: String = "vlm",
        minerUAPILanguage: String = "en",
        minerUCommand: String = "mineru",
        overwriteExistingMarkdown: Bool = true,
        pollIntervalSeconds: UInt64 = 10,
        pollTimeoutSeconds: TimeInterval = 1_800
    ) {
        self.minerUAPIToken = minerUAPIToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.minerUAPIBaseURLString = minerUAPIBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "https://mineru.net" : minerUAPIBaseURLString
        self.minerUModelVersion = minerUModelVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "vlm" : minerUModelVersion
        self.minerUAPILanguage = minerUAPILanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "en" : minerUAPILanguage
        let trimmedCommand = minerUCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        self.minerUCommand = trimmedCommand.isEmpty ? "mineru" : trimmedCommand
        self.overwriteExistingMarkdown = overwriteExistingMarkdown
        self.pollIntervalSeconds = max(1, pollIntervalSeconds)
        self.pollTimeoutSeconds = max(30, pollTimeoutSeconds)
    }
}

public actor PaperMarkdownConversionService {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func convert(
        _ papers: [Paper],
        in workspace: ResearchWorkspace,
        configuration: PaperMarkdownConversionConfiguration = PaperMarkdownConversionConfiguration()
    ) async throws -> [PaperMarkdownConversionResult] {
        var results: [PaperMarkdownConversionResult] = []
        for paper in papers {
            results.append(await convertOne(paper, in: workspace, configuration: configuration))
        }
        return results
    }

    private func convertOne(
        _ paper: Paper,
        in workspace: ResearchWorkspace,
        configuration: PaperMarkdownConversionConfiguration
    ) async -> PaperMarkdownConversionResult {
        guard let pdfURL = paper.pdfURL(in: workspace) else {
            return PaperMarkdownConversionResult(
                paperID: paper.id,
                title: paper.displayTitle,
                markdownRelativePath: nil,
                didWriteMarkdown: false,
                errorMessage: "No PDF path is configured for this paper."
            )
        }

        let markdownURL = paper.rawMarkdownURL(in: workspace)
        if FileManager.default.fileExists(atPath: markdownURL.path), !configuration.overwriteExistingMarkdown {
            return PaperMarkdownConversionResult(
                paperID: paper.id,
                title: paper.displayTitle,
                markdownRelativePath: paper.paperDirectoryRelativePath + "/paper.md",
                didWriteMarkdown: false,
                errorMessage: "paper.md already exists; overwrite is disabled."
            )
        }

        var fallbackReason = PaperMarkdownConversionError.missingMinerUAPIToken.localizedDescription
        if !configuration.minerUAPIToken.isEmpty {
            // Retry up to 2 times for transient network/TLS errors. The MinerU
            // API is remote and can fail due to proxy interference, DNS hiccups,
            // or brief TLS negotiation failures — especially common behind
            // corporate VPNs or in regions with unstable connectivity.
            var lastError: Error?
            for attempt in 1...3 {
                do {
                    let generatedMarkdown = try await convertWithMinerUAPI(
                        paper,
                        pdfURL: pdfURL,
                        markdownURL: markdownURL,
                        configuration: configuration
                    )
                    let markdown = markdownDocument(
                        for: paper,
                        pageMarkdown: generatedMarkdown,
                        extractionEngine: "mineru_api",
                        fallbackReason: nil
                    )
                    try FileManager.default.createDirectory(at: markdownURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)
                    return PaperMarkdownConversionResult(
                        paperID: paper.id,
                        title: paper.displayTitle,
                        markdownRelativePath: paper.paperDirectoryRelativePath + "/paper.md",
                        didWriteMarkdown: true,
                        errorMessage: nil,
                        extractionEngine: "mineru_api",
                        fallbackReason: nil
                    )
                } catch {
                    lastError = error
                    // Only retry on transient network/TLS errors. Non-retryable
                    // errors (auth failure, bad request, etc.) break immediately.
                    if isRetryableNetworkError(error), attempt < 3 {
                        let delay = UInt64(pow(2.0, Double(attempt - 1))) * 1_000_000_000
                        try? await Task.sleep(nanoseconds: delay)
                        continue
                    }
                    break
                }
            }
            if let lastError {
                let diagnostic = diagnosticMessage(for: lastError)
                fallbackReason = "\(lastError.localizedDescription)\(diagnostic)"
            }
        }

        guard let document = PDFDocument(url: pdfURL) else {
            return PaperMarkdownConversionResult(
                paperID: paper.id,
                title: paper.displayTitle,
                markdownRelativePath: nil,
                didWriteMarkdown: false,
                errorMessage: "Failed to load PDF."
            )
        }

        let pageMarkdown = extractedMarkdown(from: document)
        guard !pageMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return PaperMarkdownConversionResult(
                paperID: paper.id,
                title: paper.displayTitle,
                markdownRelativePath: nil,
                didWriteMarkdown: false,
                errorMessage: "PDF did not expose extractable text."
            )
        }

        let markdown = markdownDocument(
            for: paper,
            pageMarkdown: pageMarkdown,
            extractionEngine: "pdfkit_fallback",
            fallbackReason: fallbackReason
        )

        do {
            try FileManager.default.createDirectory(at: markdownURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)
            return PaperMarkdownConversionResult(
                paperID: paper.id,
                title: paper.displayTitle,
                markdownRelativePath: paper.paperDirectoryRelativePath + "/paper.md",
                didWriteMarkdown: true,
                errorMessage: nil,
                extractionEngine: "pdfkit_fallback",
                fallbackReason: fallbackReason
            )
        } catch {
            return PaperMarkdownConversionResult(
                paperID: paper.id,
                title: paper.displayTitle,
                markdownRelativePath: nil,
                didWriteMarkdown: false,
                errorMessage: error.localizedDescription
            )
        }
    }

    private func convertWithMinerUAPI(
        _ paper: Paper,
        pdfURL: URL,
        markdownURL: URL,
        configuration: PaperMarkdownConversionConfiguration
    ) async throws -> String {
        let outputDirectory = markdownURL.deletingLastPathComponent().appendingPathComponent("mineru-api-output", isDirectory: true)
        let uploadName = "\(paper.id).pdf"
        let dataID = paper.id.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "-", options: .regularExpression)

        let upload = try await createMinerUBatchUpload(
            uploadName: uploadName,
            dataID: dataID,
            configuration: configuration
        )
        try await uploadPDF(pdfURL, to: upload.uploadURL)
        let zipURL = try await pollMinerUResult(
            batchID: upload.batchID,
            uploadName: uploadName,
            dataID: dataID,
            configuration: configuration
        )
        let zipData = try await downloadMinerUZip(from: zipURL)

        if FileManager.default.fileExists(atPath: outputDirectory.path) {
            try FileManager.default.removeItem(at: outputDirectory)
        }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try extractZipData(zipData, into: outputDirectory)

        guard let generatedMarkdownURL = preferredMarkdownFile(in: outputDirectory),
              let generatedMarkdown = try? String(contentsOf: generatedMarkdownURL, encoding: .utf8),
              !generatedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PaperMarkdownConversionError.markdownNotFound
        }

        return try markdownByRestoringMinerUAssets(
            generatedMarkdown,
            generatedMarkdownURL: generatedMarkdownURL,
            outputDirectory: outputDirectory,
            markdownURL: markdownURL
        )
    }

    private func createMinerUBatchUpload(
        uploadName: String,
        dataID: String,
        configuration: PaperMarkdownConversionConfiguration
    ) async throws -> (batchID: String, uploadURL: URL) {
        let endpoint = try minerUEndpoint("/api/v4/file-urls/batch", configuration: configuration)
        var request = minerURequest(url: endpoint, method: "POST", token: configuration.minerUAPIToken)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "files": [[
                "name": uploadName,
                "data_id": dataID
            ]],
            "model_version": configuration.minerUModelVersion,
            "enable_formula": true,
            "enable_table": true,
            "language": configuration.minerUAPILanguage
        ])

        let root = try await minerUJSONResponse(for: request)
        guard let data = root["data"] as? [String: Any] else {
            throw PaperMarkdownConversionError.minerUAPIError("Missing data field.")
        }
        guard let batchID = data["batch_id"] as? String,
              !batchID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PaperMarkdownConversionError.minerUAPIError("Missing batch_id.")
        }
        guard let uploadURLString = (data["file_urls"] as? [String])?.first,
              let uploadURL = URL(string: uploadURLString) else {
            throw PaperMarkdownConversionError.missingUploadURL
        }

        return (batchID, uploadURL)
    }

    private func uploadPDF(_ pdfURL: URL, to uploadURL: URL) async throws {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.httpBody = try Data(contentsOf: pdfURL)
        let (_, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            throw PaperMarkdownConversionError.uploadFailed(statusCode)
        }
    }

    private func pollMinerUResult(
        batchID: String,
        uploadName: String,
        dataID: String,
        configuration: PaperMarkdownConversionConfiguration
    ) async throws -> URL {
        let endpoint = try minerUEndpoint("/api/v4/extract-results/batch/\(batchID)", configuration: configuration)
        let deadline = Date().addingTimeInterval(configuration.pollTimeoutSeconds)

        while Date() < deadline {
            let request = minerURequest(url: endpoint, method: "GET", token: configuration.minerUAPIToken)
            let root = try await minerUJSONResponse(for: request)
            let data = root["data"] as? [String: Any]
            let results = data?["extract_result"] as? [[String: Any]] ?? []
            let result = results.first { item in
                (item["file_name"] as? String) == uploadName || (item["data_id"] as? String) == dataID
            } ?? results.first

            if let result {
                let state = result["state"] as? String ?? ""
                if state == "done" {
                    guard let zipURLString = result["full_zip_url"] as? String,
                          let zipURL = URL(string: zipURLString) else {
                        throw PaperMarkdownConversionError.missingResultZipURL
                    }
                    return zipURL
                }
                if state == "failed" {
                    throw PaperMarkdownConversionError.resultFailed(result["err_msg"] as? String ?? "unknown error")
                }
            }

            try await Task.sleep(nanoseconds: configuration.pollIntervalSeconds * 1_000_000_000)
        }

        throw PaperMarkdownConversionError.resultTimedOut
    }

    private func downloadMinerUZip(from zipURL: URL) async throws -> Data {
        let (data, response) = try await session.data(from: zipURL)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode), !data.isEmpty else {
            throw PaperMarkdownConversionError.missingResultZipURL
        }
        return data
    }

    private func minerUJSONResponse(for request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            throw PaperMarkdownConversionError.minerUAPIError(String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PaperMarkdownConversionError.minerUAPIError("Malformed JSON response.")
        }
        let code = root["code"] as? Int ?? -1
        guard code == 0 else {
            throw PaperMarkdownConversionError.minerUAPIError(root["msg"] as? String ?? "code=\(code)")
        }
        return root
    }

    private nonisolated func minerURequest(url: URL, method: String, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private nonisolated func minerUEndpoint(_ path: String, configuration: PaperMarkdownConversionConfiguration) throws -> URL {
        let baseURLString = configuration.minerUAPIBaseURLString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !baseURLString.isEmpty,
              let url = URL(string: baseURLString + path) else {
            throw PaperMarkdownConversionError.invalidMinerUAPIBaseURL(configuration.minerUAPIBaseURLString)
        }
        return url
    }

    private nonisolated func extractZipData(_ zipData: Data, into directory: URL) throws {
        let zipURL = directory.appendingPathComponent("mineru-result.zip", isDirectory: false)
        try zipData.write(to: zipURL, options: .atomic)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-oq", zipURL.path, "-d", directory.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw PaperMarkdownConversionError.badZipArchive
        }
    }

    private nonisolated func preferredMarkdownFile(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let markdownFiles = enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "md" }

        if let fullMarkdown = markdownFiles.first(where: { $0.lastPathComponent == "full.md" }) {
            return fullMarkdown
        }

        return markdownFiles.sorted { first, second in
            let firstSize = (try? first.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let secondSize = (try? second.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return firstSize > secondSize
        }.first
    }

    private nonisolated func isRetryableNetworkError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .secureConnectionFailed,    // TLS error
                 .timedOut,
                 .networkConnectionLost,
                 .notConnectedToInternet,
                 .dnsLookupFailed,
                 .cannotConnectToHost,
                 .cannotFindHost:
                return true
            default:
                return false
            }
        }
        // NSError domain check for generic network failures.
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return [-1200, -1001, -1005, -1009, -1003, -1004].contains(nsError.code)
        }
        return false
    }

    private nonisolated func diagnosticMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .secureConnectionFailed:
                return " [诊断: TLS 握手失败。如果您使用了 VPN 或代理，请检查其是否拦截了 HTTPS 连接。也可以尝试在系统设置中信任代理证书，或暂时关闭代理后重试。]"
            case .timedOut:
                return " [诊断: 连接超时。请检查网络连接是否稳定。]"
            case .notConnectedToInternet:
                return " [诊断: 无网络连接。请检查 Wi-Fi 或有线网络。]"
            case .dnsLookupFailed, .cannotFindHost:
                return " [诊断: DNS 解析失败。请检查 mineru.net 是否可访问，或尝试更换 DNS 服务器。]"
            default:
                return ""
            }
        }
        return ""
    }

    private nonisolated func markdownByRestoringMinerUAssets(
        _ markdown: String,
        generatedMarkdownURL: URL,
        outputDirectory: URL,
        markdownURL: URL
    ) throws -> String {
        let assetDirectory = markdownURL
            .deletingLastPathComponent()
            .appendingPathComponent("figures", isDirectory: true)
            .appendingPathComponent("mineru", isDirectory: true)

        if FileManager.default.fileExists(atPath: assetDirectory.path) {
            try FileManager.default.removeItem(at: assetDirectory)
        }

        var copiedAssetPathsBySource: [String: String] = [:]
        let imagePattern = #"!\[[^\]]*\]\(([^)\n]+)\)"#
        let imageLinkedMarkdown = try rewriteMinerULocalAssetReferences(
            in: markdown,
            pattern: imagePattern,
            captureGroup: 1,
            generatedMarkdownURL: generatedMarkdownURL,
            outputDirectory: outputDirectory,
            assetDirectory: assetDirectory,
            copiedAssetPathsBySource: &copiedAssetPathsBySource,
            preservesMarkdownDestinationSuffix: true
        )
        let htmlImagePattern = #"<img\b[^>]*\bsrc\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#
        return try rewriteMinerULocalAssetReferences(
            in: imageLinkedMarkdown,
            pattern: htmlImagePattern,
            captureGroup: 1,
            generatedMarkdownURL: generatedMarkdownURL,
            outputDirectory: outputDirectory,
            assetDirectory: assetDirectory,
            copiedAssetPathsBySource: &copiedAssetPathsBySource,
            preservesMarkdownDestinationSuffix: false
        )
    }

    private nonisolated func rewriteMinerULocalAssetReferences(
        in markdown: String,
        pattern: String,
        captureGroup: Int,
        generatedMarkdownURL: URL,
        outputDirectory: URL,
        assetDirectory: URL,
        copiedAssetPathsBySource: inout [String: String],
        preservesMarkdownDestinationSuffix: Bool
    ) throws -> String {
        let expression = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let mutableMarkdown = NSMutableString(string: markdown)
        let fullRange = NSRange(location: 0, length: mutableMarkdown.length)
        let matches = expression.matches(in: markdown, options: [], range: fullRange)

        for match in matches.reversed() {
            let destinationRange = match.range(at: captureGroup)
            guard destinationRange.location != NSNotFound else {
                continue
            }

            let originalDestination = mutableMarkdown.substring(with: destinationRange)
            let pathToken: MinerUMarkdownPathToken
            if preservesMarkdownDestinationSuffix {
                guard let parsedPathToken = minerUMarkdownPathToken(from: originalDestination) else {
                    continue
                }
                pathToken = parsedPathToken
            } else {
                pathToken = MinerUMarkdownPathToken(prefix: "", path: originalDestination, suffix: "", usesAngleBrackets: false)
            }

            guard let sourceURL = minerULocalAssetURL(
                for: pathToken.path,
                relativeTo: generatedMarkdownURL.deletingLastPathComponent(),
                outputDirectory: outputDirectory
            ) else {
                continue
            }

            let sourceKey = sourceURL.standardizedFileURL.path
            let stableRelativePath: String
            if let copiedPath = copiedAssetPathsBySource[sourceKey] {
                stableRelativePath = copiedPath
            } else {
                stableRelativePath = try copyMinerULocalAsset(
                    from: sourceURL,
                    outputDirectory: outputDirectory,
                    assetDirectory: assetDirectory
                )
                copiedAssetPathsBySource[sourceKey] = stableRelativePath
            }

            let replacement = pathToken.replacingPath(with: stableRelativePath)
            mutableMarkdown.replaceCharacters(in: destinationRange, with: replacement)
        }

        return mutableMarkdown as String
    }

    private nonisolated func minerUMarkdownPathToken(from destination: String) -> MinerUMarkdownPathToken? {
        let leadingWhitespaceLength = destination.prefix { $0.isWhitespace }.count
        let prefix = String(destination.prefix(leadingWhitespaceLength))
        let rest = String(destination.dropFirst(leadingWhitespaceLength))
        guard !rest.isEmpty else {
            return nil
        }

        if rest.first == "<", let closeIndex = rest.firstIndex(of: ">") {
            let pathStart = rest.index(after: rest.startIndex)
            let path = String(rest[pathStart..<closeIndex])
            let suffix = String(rest[rest.index(after: closeIndex)...])
            return MinerUMarkdownPathToken(prefix: prefix, path: path, suffix: suffix, usesAngleBrackets: true)
        }

        let pathEnd = rest.firstIndex { $0.isWhitespace } ?? rest.endIndex
        let path = String(rest[..<pathEnd])
        let suffix = String(rest[pathEnd...])
        return MinerUMarkdownPathToken(prefix: prefix, path: path, suffix: suffix, usesAngleBrackets: false)
    }

    private nonisolated func minerULocalAssetURL(for rawPath: String, relativeTo baseDirectory: URL, outputDirectory: URL) -> URL? {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty,
              !path.hasPrefix("#"),
              !path.hasPrefix("data:"),
              !path.hasPrefix("mailto:"),
              URLComponents(string: path)?.scheme == nil else {
            return nil
        }

        let pathWithoutSuffix = path.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? path
        let pathWithoutQuery = pathWithoutSuffix.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? pathWithoutSuffix
        let decodedPath = pathWithoutQuery.removingPercentEncoding ?? pathWithoutQuery

        let candidateURL: URL
        if decodedPath.hasPrefix("/") {
            candidateURL = URL(fileURLWithPath: decodedPath)
        } else {
            candidateURL = baseDirectory.appendingPathComponent(decodedPath)
        }

        if isMinerUAsset(candidateURL, inside: outputDirectory) {
            return candidateURL.standardizedFileURL
        }

        return minerUAssetURLMatchingLastPathComponent(decodedPath, in: outputDirectory)
    }

    private nonisolated func minerUAssetURLMatchingLastPathComponent(_ path: String, in outputDirectory: URL) -> URL? {
        let lastPathComponent = URL(fileURLWithPath: path).lastPathComponent
        guard !lastPathComponent.isEmpty,
              let enumerator = FileManager.default.enumerator(
                at: outputDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return nil
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent == lastPathComponent,
                  isMinerUAsset(fileURL, inside: outputDirectory) else {
                continue
            }
            return fileURL.standardizedFileURL
        }

        return nil
    }

    private nonisolated func isMinerUAsset(_ url: URL, inside outputDirectory: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        let outputPath = outputDirectory.standardizedFileURL.path
        let assetPath = standardizedURL.path
        guard assetPath == outputPath || assetPath.hasPrefix(outputPath + "/") else {
            return false
        }
        guard supportedMinerUAssetExtensions.contains(standardizedURL.pathExtension.lowercased()) else {
            return false
        }
        return (try? standardizedURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private nonisolated var supportedMinerUAssetExtensions: Set<String> {
        ["apng", "bmp", "gif", "jpeg", "jpg", "png", "svg", "tif", "tiff", "webp"]
    }

    private nonisolated func copyMinerULocalAsset(from sourceURL: URL, outputDirectory: URL, assetDirectory: URL) throws -> String {
        let relativeComponents = minerURelativePathComponents(for: sourceURL, outputDirectory: outputDirectory)
        let safeComponents = relativeComponents.map(sanitizedMinerUAssetPathComponent)
        let relativePath = safeComponents.joined(separator: "/")
        let destinationURL = safeComponents.reduce(assetDirectory) { partialURL, component in
            partialURL.appendingPathComponent(component, isDirectory: false)
        }

        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        return "figures/mineru/" + relativePath
    }

    private nonisolated func minerURelativePathComponents(for sourceURL: URL, outputDirectory: URL) -> [String] {
        let outputPath = outputDirectory.standardizedFileURL.path
        let sourcePath = sourceURL.standardizedFileURL.path
        let relativePath: String
        if sourcePath.hasPrefix(outputPath + "/") {
            relativePath = String(sourcePath.dropFirst(outputPath.count + 1))
        } else {
            relativePath = sourceURL.lastPathComponent
        }

        let components = relativePath.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0 != "." && $0 != ".." }
        return components.isEmpty ? [sourceURL.lastPathComponent] : components
    }

    private nonisolated func sanitizedMinerUAssetPathComponent(_ component: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = component.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let sanitized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        return sanitized.isEmpty ? "asset" : sanitized
    }

    private nonisolated func extractedMarkdown(from document: PDFDocument) -> String {
        var sections: [String] = []
        for pageIndex in 0..<document.pageCount {
            guard let text = document.page(at: pageIndex)?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                continue
            }

            sections.append("## Page \(pageIndex + 1)\n\n\(text)")
        }

        return sections.joined(separator: "\n\n")
    }

    private nonisolated func markdownDocument(
        for paper: Paper,
        pageMarkdown: String,
        extractionEngine: String,
        fallbackReason: String?
    ) -> String {
        let authors = paper.authors.isEmpty ? "[]" : "[" + paper.authors.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ", ") + "]"
        let tags = paper.tags.isEmpty ? "[]" : "[" + paper.tags.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ", ") + "]"
        let categories = paper.categories.isEmpty ? "[]" : "[" + paper.categories.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ", ") + "]"

        return """
        ---
        type: paper_raw_markdown
        extraction_engine: \(extractionEngine)
        mineru_compatible: true
        extracted_at: "\(ISO8601DateFormatter().string(from: Date()))"
        fallback_reason: "\((fallbackReason ?? "").replacingOccurrences(of: "\"", with: "\\\""))"
        paper_id: \(paper.id)
        citekey: \(paper.citekey)
        title: "\(paper.displayTitle.replacingOccurrences(of: "\"", with: "\\\""))"
        authors: \(authors)
        year: \(paper.year.map(String.init) ?? "")
        venue: "\((paper.publicationTitle ?? paper.venue ?? "").replacingOccurrences(of: "\"", with: "\\\""))"
        doi: "\((paper.doi ?? "").replacingOccurrences(of: "\"", with: "\\\""))"
        arxiv: "\((paper.arxiv ?? "").replacingOccurrences(of: "\"", with: "\\\""))"
        tags: \(tags)
        categories: \(categories)
        source_pdf: "\(paper.pdfRelativePath ?? "paper.pdf")"
        ---

        # \(paper.displayTitle)

        > Generated by Sci-Station's PDF-to-Markdown bridge using \(extractionEngine).

        \(pageMarkdown)
        """
    }
}

private struct MinerUMarkdownPathToken {
    let prefix: String
    let path: String
    let suffix: String
    let usesAngleBrackets: Bool

    nonisolated func replacingPath(with replacement: String) -> String {
        if usesAngleBrackets {
            return prefix + "<" + replacement + ">" + suffix
        }
        return prefix + replacement + suffix
    }
}
