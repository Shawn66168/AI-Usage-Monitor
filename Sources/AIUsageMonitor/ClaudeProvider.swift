import Foundation

struct ClaudeProvider: UsageProvider {
    let kind: ServiceKind = .claude
    private let statusURL: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.statusURL = homeDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("usage-status.json")
    }

    func fetchSnapshot() async -> AIServiceSnapshot {
        do {
            let data = try Data(contentsOf: statusURL)
            let payload = try JSONDecoder().decode(ClaudeStatusPayload.self, from: data)
            return try payload.makeSnapshot(sourcePath: statusURL.path)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .placeholder(
                for: kind,
                status: .unavailable("請先啟動 Claude Code，等待它產生用量狀態快照"),
                source: statusURL.path
            )
        } catch {
            return .placeholder(
                for: kind,
                status: .error(error.localizedDescription),
                source: statusURL.path
            )
        }
    }
}

private struct ClaudeStatusPayload: Decodable {
    let receivedAt: String?
    let model: ClaudeModel?
    let contextWindow: ClaudeContextWindow?
    let cost: ClaudeCost?
    let rateLimits: ClaudeRateLimits?

    enum CodingKeys: String, CodingKey {
        case receivedAt = "_received_at"
        case model
        case contextWindow = "context_window"
        case cost
        case rateLimits = "rate_limits"
    }

    func makeSnapshot(sourcePath: String) throws -> AIServiceSnapshot {
        let fetchedAt = receivedAt.flatMap(FlexibleDateParser.parse) ?? Date()
        let age = Date().timeIntervalSince(fetchedAt)
        let status: ProviderStatus = age > 15 * 60
            ? ProviderStatus(state: .stale, message: "Claude 快照已超過 15 分鐘；啟動 Claude Code 後會自動刷新")
            : .available

        var quotas: [QuotaWindow] = []
        if let fiveHour = rateLimits?.fiveHour {
            quotas.append(
                QuotaWindow(
                    id: "claude-five-hour",
                    label: "5 小時用量",
                    usedPercent: fiveHour.usedPercentage,
                    resetsAt: fiveHour.resetsAt.map { Date(timeIntervalSince1970: $0) },
                    scope: .rolling
                )
            )
        }
        if let sevenDay = rateLimits?.sevenDay {
            quotas.append(
                QuotaWindow(
                    id: "claude-seven-day",
                    label: "7 天用量",
                    usedPercent: sevenDay.usedPercentage,
                    resetsAt: sevenDay.resetsAt.map { Date(timeIntervalSince1970: $0) },
                    scope: .weekly
                )
            )
        }

        var tokenUsage: TokenUsage?
        var contextUsage: ContextUsage?
        if let contextWindow {
            let current = contextWindow.currentUsage
            let totalInput = contextWindow.totalInputTokens
                ?? ((current?.inputTokens ?? 0) + (current?.cacheCreationInputTokens ?? 0) + (current?.cacheReadInputTokens ?? 0))
            let totalOutput = contextWindow.totalOutputTokens ?? current?.outputTokens ?? 0
            let total = totalInput + totalOutput

            tokenUsage = TokenUsage(
                inputTokens: current?.inputTokens ?? 0,
                cachedInputTokens: current?.cacheReadInputTokens ?? 0,
                cacheWriteInputTokens: current?.cacheCreationInputTokens ?? 0,
                outputTokens: totalOutput,
                totalTokens: total,
                periodLabel: "目前 Claude Code 工作階段"
            )

            if let windowSize = contextWindow.contextWindowSize, windowSize > 0 {
                contextUsage = ContextUsage(
                    usedTokens: total,
                    windowTokens: windowSize,
                    usedPercent: contextWindow.usedPercentage,
                    modelName: model?.displayName ?? model?.id
                )
            }
        }

        let costUsage = cost?.totalCostUSD.map {
            CostUsage(amountUSD: max(0, $0), periodLabel: "目前 Claude Code 工作階段估算")
        }

        return AIServiceSnapshot(
            id: .claude,
            planName: model?.displayName ?? model?.id,
            quotas: quotas,
            tokenUsage: tokenUsage,
            contextUsage: contextUsage,
            costUsage: costUsage,
            status: status,
            sourceDescription: "Claude Code 本機快照",
            fetchedAt: fetchedAt
        )
    }
}

private struct ClaudeModel: Decodable {
    let id: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

private struct ClaudeContextWindow: Decodable {
    let totalInputTokens: Int64?
    let totalOutputTokens: Int64?
    let contextWindowSize: Int64?
    let currentUsage: ClaudeCurrentUsage?
    let usedPercentage: Double?

    enum CodingKeys: String, CodingKey {
        case totalInputTokens = "total_input_tokens"
        case totalOutputTokens = "total_output_tokens"
        case contextWindowSize = "context_window_size"
        case currentUsage = "current_usage"
        case usedPercentage = "used_percentage"
    }
}

private struct ClaudeCurrentUsage: Decodable {
    let inputTokens: Int64?
    let outputTokens: Int64?
    let cacheCreationInputTokens: Int64?
    let cacheReadInputTokens: Int64?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }
}

private struct ClaudeCost: Decodable {
    let totalCostUSD: Double?

    enum CodingKeys: String, CodingKey {
        case totalCostUSD = "total_cost_usd"
    }
}

private struct ClaudeRateLimits: Decodable {
    let fiveHour: ClaudeRateLimitWindow?
    let sevenDay: ClaudeRateLimitWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private struct ClaudeRateLimitWindow: Decodable {
    let usedPercentage: Double
    let resetsAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }
}

enum FlexibleDateParser {
    static func parse(_ string: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: string) {
            return date
        }

        let standardFormatter = ISO8601DateFormatter()
        return standardFormatter.date(from: string)
    }
}
