import Foundation

struct CodexProvider: UsageProvider {
    let kind: ServiceKind = .codex
    private let homeDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    func fetchSnapshot() async -> AIServiceSnapshot {
        async let quotaResult = fetchRateLimits()
        async let tokenResult = fetchLocalTokenUsage()

        let quota = await quotaResult
        let localUsage = await tokenResult

        switch quota {
        case let .success(rateLimits):
            return AIServiceSnapshot(
                id: .codex,
                planName: rateLimits.planType?.capitalized,
                quotas: rateLimits.quotaWindows,
                tokenUsage: localUsage.tokenUsage,
                contextUsage: localUsage.contextUsage,
                status: .available,
                sourceDescription: "Codex 官方 app-server＋本機 token_count",
                fetchedAt: Date()
            )
        case let .failure(error):
            let status: ProviderStatus
            if error.localizedDescription.localizedCaseInsensitiveContains("login")
                || error.localizedDescription.localizedCaseInsensitiveContains("auth") {
                status = .unavailable("Codex 尚未登入，或無法取得帳戶額度")
            } else {
                status = .error(error.localizedDescription)
            }

            return AIServiceSnapshot(
                id: .codex,
                quotas: [],
                tokenUsage: localUsage.tokenUsage,
                contextUsage: localUsage.contextUsage,
                status: status,
                sourceDescription: "Codex 本機 session 紀錄",
                fetchedAt: Date()
            )
        }
    }

    private func fetchRateLimits() async -> Result<CodexRateLimitSnapshot, Error> {
        do {
            let executable = try resolveCodexExecutable()
            let output = try await CodexAppServerClient.readRateLimits(executable: executable)
            return .success(output)
        } catch {
            return .failure(error)
        }
    }

    private func resolveCodexExecutable() throws -> URL {
        let candidates = [
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
            homeDirectory.appendingPathComponent("Applications/ChatGPT.app/Contents/Resources/codex"),
            URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"),
            homeDirectory.appendingPathComponent("Applications/Codex.app/Contents/Resources/codex"),
            homeDirectory.appendingPathComponent(".local/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex")
        ]

        guard let executable = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            throw ProviderError.executableNotFound("Codex")
        }
        return executable
    }

    private func fetchLocalTokenUsage() async -> CodexLocalUsage {
        let homeDirectory = self.homeDirectory
        return await Task.detached(priority: .utility) {
            CodexSessionAnalyzer(homeDirectory: homeDirectory).analyzeLastSevenDays()
        }.value
    }
}

private enum CodexAppServerClient {
    static func readRateLimits(executable: URL) async throws -> CodexRateLimitSnapshot {
        try await Task.detached(priority: .utility) {
            try readRateLimitsSynchronously(executable: executable)
        }.value
    }

    private static func readRateLimitsSynchronously(executable: URL) throws -> CodexRateLimitSnapshot {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()
        let buffer = LockedOutputBuffer()
        let signal = DispatchSemaphore(value: 0)

        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            buffer.append(data)
            signal.signal()
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            throw ProviderError.processFailed(error.localizedDescription)
        }

        let initialize = #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"ai-usage-monitor","title":"AI Usage Monitor","version":"0.1.0"},"capabilities":null}}"#
        let rateLimits = #"{"id":2,"method":"account/rateLimits/read"}"#

        if let data = "\(initialize)\n\(rateLimits)\n".data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(data)
        }

        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline, !buffer.containsResponse(id: 2) {
            _ = signal.wait(timeout: .now() + 0.3)
        }

        try? inputPipe.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()
        outputPipe.fileHandleForReading.readabilityHandler = nil

        let output = buffer.string
        let stderr = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        guard buffer.containsResponse(id: 2) else {
            let reason = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ProviderError.timedOut(reason.isEmpty ? "Codex 額度讀取" : reason)
        }

        let decoder = JSONDecoder()
        for line in output.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8),
                  let envelope = try? decoder.decode(CodexRPCEnvelope.self, from: data),
                  envelope.id == 2 else {
                continue
            }

            if let message = envelope.error?.message {
                throw ProviderError.processFailed(message)
            }
            guard let snapshot = envelope.result?.rateLimits else {
                throw ProviderError.invalidData("Codex 未回傳 rateLimits")
            }
            return snapshot
        }

        throw ProviderError.invalidData("找不到 Codex 額度回應")
    }
}

private final class LockedOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ newData: Data) {
        lock.lock()
        data.append(newData)
        lock.unlock()
    }

    var string: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func containsResponse(id: Int) -> Bool {
        let pattern = "\"id\":\(id)"
        return string.contains(pattern)
    }
}

private struct CodexRPCEnvelope: Decodable {
    let id: Int?
    let result: CodexRateLimitResult?
    let error: CodexRPCError?
}

private struct CodexRPCError: Decodable {
    let message: String?
}

private struct CodexRateLimitResult: Decodable {
    let rateLimits: CodexRateLimitSnapshot?
}

private struct CodexRateLimitSnapshot: Decodable, Sendable {
    let limitId: String?
    let limitName: String?
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
    let credits: CodexCredits?
    let planType: String?

    var quotaWindows: [QuotaWindow] {
        let windows = [primary, secondary].compactMap { $0 }
        let fiveHour = windows.first { $0.windowDurationMins > 0 && $0.windowDurationMins < 24 * 60 }
        let weekly = windows.first { $0.windowDurationMins >= 7 * 24 * 60 }

        var result: [QuotaWindow] = []
        if let fiveHour {
            result.append(
                QuotaWindow(
                    id: "codex-five-hour",
                    label: "5 小時用量",
                    usedPercent: fiveHour.usedPercent,
                    resetsAt: fiveHour.resetDate,
                    scope: .rolling
                )
            )
        }
        if let weekly {
            result.append(
                QuotaWindow(
                    id: "codex-weekly",
                    label: "每週用量",
                    usedPercent: weekly.usedPercent,
                    resetsAt: weekly.resetDate,
                    scope: .weekly
                )
            )
        }

        if let credits, credits.hasCredits || credits.unlimited {
            result.append(
                QuotaWindow(
                    id: "codex-credits",
                    label: "額外 Credits",
                    remainingPercent: credits.unlimited ? 100 : 0,
                    scope: .credits,
                    detail: credits.unlimited ? "Unlimited" : "餘額 \(credits.balance ?? "—")"
                )
            )
        }
        return result
    }
}

private struct CodexRateLimitWindow: Decodable, Sendable {
    let usedPercent: Double
    let windowDurationMins: Int
    let resetsAt: TimeInterval?

    var resetDate: Date? {
        resetsAt.map { Date(timeIntervalSince1970: $0) }
    }
}

private struct CodexCredits: Decodable, Sendable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?
}

private struct CodexLocalUsage: Sendable {
    var tokenUsage: TokenUsage?
    var contextUsage: ContextUsage?
}

private struct CodexSessionAnalyzer: Sendable {
    let homeDirectory: URL

    func analyzeLastSevenDays(now: Date = Date()) -> CodexLocalUsage {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let codexRoot = homeDirectory.appendingPathComponent(".codex", isDirectory: true)
        let roots = [
            codexRoot.appendingPathComponent("sessions", isDirectory: true),
            codexRoot.appendingPathComponent("archived_sessions", isDirectory: true)
        ]

        var totals = TokenAccumulator()
        var latestContext: ContextCandidate?

        for root in roots {
            for fileURL in recentJSONLFiles(root: root, modifiedAfter: startDate) {
                analyze(fileURL: fileURL, startDate: startDate, totals: &totals, latestContext: &latestContext)
            }
        }

        let tokenUsage: TokenUsage? = totals.events > 0
            ? TokenUsage(
                inputTokens: totals.inputTokens,
                cachedInputTokens: totals.cachedInputTokens,
                cacheWriteInputTokens: totals.cacheWriteInputTokens,
                outputTokens: totals.outputTokens,
                reasoningOutputTokens: totals.reasoningOutputTokens,
                totalTokens: totals.totalTokens,
                periodLabel: "近 7 天（僅此 Mac）"
            )
            : nil

        let contextUsage: ContextUsage? = latestContext.flatMap { candidate in
            guard candidate.windowTokens > 0 else { return nil }
            return ContextUsage(
                usedTokens: candidate.usedTokens,
                windowTokens: candidate.windowTokens,
                modelName: "最新 Codex session"
            )
        }

        return CodexLocalUsage(tokenUsage: tokenUsage, contextUsage: contextUsage)
    }

    private func recentJSONLFiles(root: URL, modifiedAfter: Date) -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl",
                  let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt >= modifiedAfter else {
                continue
            }
            files.append(fileURL)
        }
        return files
    }

    private func analyze(
        fileURL: URL,
        startDate: Date,
        totals: inout TokenAccumulator,
        latestContext: inout ContextCandidate?
    ) {
        guard let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8) else {
            return
        }

        let decoder = JSONDecoder()
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.contains("\"token_count\""),
                  let lineData = String(line).data(using: .utf8),
                  let event = try? decoder.decode(CodexTokenEvent.self, from: lineData),
                  event.type == "event_msg",
                  event.payload.type == "token_count",
                  let timestamp = FlexibleDateParser.parse(event.timestamp),
                  timestamp >= startDate,
                  let usage = event.payload.info?.lastTokenUsage else {
                continue
            }

            totals.add(usage)

            if let total = event.payload.info?.totalTokenUsage,
               let window = event.payload.info?.modelContextWindow,
               latestContext == nil || timestamp > latestContext!.timestamp {
                latestContext = ContextCandidate(
                    timestamp: timestamp,
                    usedTokens: max(0, total.totalTokens),
                    windowTokens: max(0, window)
                )
            }
        }
    }
}

private struct TokenAccumulator {
    var inputTokens: Int64 = 0
    var cachedInputTokens: Int64 = 0
    var cacheWriteInputTokens: Int64 = 0
    var outputTokens: Int64 = 0
    var reasoningOutputTokens: Int64 = 0
    var totalTokens: Int64 = 0
    var events = 0

    mutating func add(_ usage: CodexTokenUsagePayload) {
        inputTokens += max(0, usage.inputTokens)
        cachedInputTokens += max(0, usage.cachedInputTokens)
        cacheWriteInputTokens += max(0, usage.cacheWriteInputTokens)
        outputTokens += max(0, usage.outputTokens)
        reasoningOutputTokens += max(0, usage.reasoningOutputTokens)
        totalTokens += max(0, usage.totalTokens)
        events += 1
    }
}

private struct ContextCandidate {
    let timestamp: Date
    let usedTokens: Int64
    let windowTokens: Int64
}

private struct CodexTokenEvent: Decodable {
    let timestamp: String
    let type: String
    let payload: CodexTokenPayload
}

private struct CodexTokenPayload: Decodable {
    let type: String
    let info: CodexTokenInfo?
}

private struct CodexTokenInfo: Decodable {
    let totalTokenUsage: CodexTokenUsagePayload?
    let lastTokenUsage: CodexTokenUsagePayload?
    let modelContextWindow: Int64?

    enum CodingKeys: String, CodingKey {
        case totalTokenUsage = "total_token_usage"
        case lastTokenUsage = "last_token_usage"
        case modelContextWindow = "model_context_window"
    }
}

private struct CodexTokenUsagePayload: Decodable {
    let inputTokens: Int64
    let cachedInputTokens: Int64
    let cacheWriteInputTokens: Int64
    let outputTokens: Int64
    let reasoningOutputTokens: Int64
    let totalTokens: Int64

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case cacheWriteInputTokens = "cache_write_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningOutputTokens = "reasoning_output_tokens"
        case totalTokens = "total_tokens"
    }
}
