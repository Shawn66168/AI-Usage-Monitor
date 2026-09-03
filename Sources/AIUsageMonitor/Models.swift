import Foundation
import SwiftUI

enum ServiceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case antigravity
    case chatGPT
    case manus
    case anthropicAPI
    case openAIAPI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude / Claude Code"
        case .codex: "Codex"
        case .antigravity: "Antigravity"
        case .chatGPT: "ChatGPT"
        case .manus: "Manus"
        case .anthropicAPI: "Anthropic API"
        case .openAIAPI: "OpenAI API"
        }
    }

    var shortName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .antigravity: "Antigravity"
        case .chatGPT: "ChatGPT"
        case .manus: "Manus"
        case .anthropicAPI: "Anthropic API"
        case .openAIAPI: "OpenAI API"
        }
    }

    var symbolName: String {
        switch self {
        case .claude: "sparkles"
        case .codex: "terminal.fill"
        case .antigravity: "arrow.up.and.down.and.arrow.left.and.right"
        case .chatGPT: "bubble.left.and.text.bubble.right.fill"
        case .manus: "hand.raised.fill"
        case .anthropicAPI: "server.rack"
        case .openAIAPI: "network"
        }
    }

    var tint: Color {
        switch self {
        case .claude: Color(red: 0.80, green: 0.39, blue: 0.22)
        case .codex: Color(red: 0.16, green: 0.68, blue: 0.55)
        case .antigravity: Color(red: 0.32, green: 0.51, blue: 0.96)
        case .chatGPT: Color(red: 0.20, green: 0.57, blue: 0.46)
        case .manus: Color(red: 0.48, green: 0.39, blue: 0.90)
        case .anthropicAPI: Color(red: 0.72, green: 0.42, blue: 0.27)
        case .openAIAPI: Color(red: 0.16, green: 0.60, blue: 0.51)
        }
    }
}

enum ProviderState: String, Codable, Sendable {
    case available
    case stale
    case loading
    case unavailable
    case unsupported
    case needsConfiguration
    case error

    var label: String {
        switch self {
        case .available: "即時"
        case .stale: "快取"
        case .loading: "更新中"
        case .unavailable: "未連線"
        case .unsupported: "官方未提供"
        case .needsConfiguration: "待設定"
        case .error: "發生錯誤"
        }
    }
}

struct ProviderStatus: Codable, Sendable, Equatable {
    var state: ProviderState
    var message: String?

    static let available = ProviderStatus(state: .available, message: nil)

    static func unavailable(_ message: String) -> ProviderStatus {
        ProviderStatus(state: .unavailable, message: message)
    }

    static func unsupported(_ message: String) -> ProviderStatus {
        ProviderStatus(state: .unsupported, message: message)
    }

    static func needsConfiguration(_ message: String) -> ProviderStatus {
        ProviderStatus(state: .needsConfiguration, message: message)
    }

    static func error(_ message: String) -> ProviderStatus {
        ProviderStatus(state: .error, message: message)
    }
}

enum QuotaScope: String, Codable, Sendable {
    case rolling
    case weekly
    case monthly
    case model
    case credits
    case organization
    case unknown
}

struct QuotaWindow: Identifiable, Codable, Sendable, Equatable {
    var id: String
    var label: String
    var usedPercent: Double
    var remainingPercent: Double
    var resetsAt: Date?
    var scope: QuotaScope
    var detail: String?

    init(
        id: String,
        label: String,
        usedPercent: Double,
        remainingPercent: Double? = nil,
        resetsAt: Date? = nil,
        scope: QuotaScope,
        detail: String? = nil
    ) {
        let normalizedUsed = usedPercent.clamped(to: 0 ... 100)
        self.id = id
        self.label = label
        self.usedPercent = normalizedUsed
        self.remainingPercent = (remainingPercent ?? (100 - normalizedUsed)).clamped(to: 0 ... 100)
        self.resetsAt = resetsAt
        self.scope = scope
        self.detail = detail
    }

    init(
        id: String,
        label: String,
        remainingPercent: Double,
        resetsAt: Date? = nil,
        scope: QuotaScope,
        detail: String? = nil
    ) {
        let normalizedRemaining = remainingPercent.clamped(to: 0 ... 100)
        self.init(
            id: id,
            label: label,
            usedPercent: 100 - normalizedRemaining,
            remainingPercent: normalizedRemaining,
            resetsAt: resetsAt,
            scope: scope,
            detail: detail
        )
    }
}

struct TokenUsage: Codable, Sendable, Equatable {
    var inputTokens: Int64
    var cachedInputTokens: Int64
    var cacheWriteInputTokens: Int64
    var outputTokens: Int64
    var reasoningOutputTokens: Int64
    var totalTokens: Int64
    var periodLabel: String

    init(
        inputTokens: Int64 = 0,
        cachedInputTokens: Int64 = 0,
        cacheWriteInputTokens: Int64 = 0,
        outputTokens: Int64 = 0,
        reasoningOutputTokens: Int64 = 0,
        totalTokens: Int64? = nil,
        periodLabel: String
    ) {
        self.inputTokens = max(0, inputTokens)
        self.cachedInputTokens = max(0, cachedInputTokens)
        self.cacheWriteInputTokens = max(0, cacheWriteInputTokens)
        self.outputTokens = max(0, outputTokens)
        self.reasoningOutputTokens = max(0, reasoningOutputTokens)
        self.totalTokens = max(
            0,
            totalTokens ?? (inputTokens + cacheWriteInputTokens + outputTokens)
        )
        self.periodLabel = periodLabel
    }
}

struct ContextUsage: Codable, Sendable, Equatable {
    var usedTokens: Int64
    var windowTokens: Int64
    var usedPercent: Double
    var modelName: String?

    init(
        usedTokens: Int64,
        windowTokens: Int64,
        usedPercent: Double? = nil,
        modelName: String? = nil
    ) {
        self.usedTokens = max(0, usedTokens)
        self.windowTokens = max(0, windowTokens)
        if let usedPercent {
            self.usedPercent = usedPercent.clamped(to: 0 ... 100)
        } else if windowTokens > 0 {
            self.usedPercent = (Double(usedTokens) / Double(windowTokens) * 100).clamped(to: 0 ... 100)
        } else {
            self.usedPercent = 0
        }
        self.modelName = modelName
    }

    var remainingTokens: Int64 {
        max(0, windowTokens - usedTokens)
    }
}

struct CostUsage: Codable, Sendable, Equatable {
    var amountUSD: Double
    var periodLabel: String
}

struct AIServiceSnapshot: Identifiable, Codable, Sendable, Equatable {
    var id: ServiceKind
    var displayName: String
    var planName: String?
    var quotas: [QuotaWindow]
    var tokenUsage: TokenUsage?
    var contextUsage: ContextUsage?
    var costUsage: CostUsage?
    var status: ProviderStatus
    var sourceDescription: String
    var fetchedAt: Date

    init(
        id: ServiceKind,
        displayName: String? = nil,
        planName: String? = nil,
        quotas: [QuotaWindow] = [],
        tokenUsage: TokenUsage? = nil,
        contextUsage: ContextUsage? = nil,
        costUsage: CostUsage? = nil,
        status: ProviderStatus,
        sourceDescription: String,
        fetchedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName ?? id.displayName
        self.planName = planName
        self.quotas = quotas
        self.tokenUsage = tokenUsage
        self.contextUsage = contextUsage
        self.costUsage = costUsage
        self.status = status
        self.sourceDescription = sourceDescription
        self.fetchedAt = fetchedAt
    }

    var lowestRemainingPercent: Double? {
        quotas.map(\.remainingPercent).min()
    }

    static func placeholder(
        for kind: ServiceKind,
        status: ProviderStatus,
        source: String
    ) -> AIServiceSnapshot {
        AIServiceSnapshot(
            id: kind,
            status: status,
            sourceDescription: source
        )
    }
}

struct AppPreferences: Codable, Sendable, Equatable {
    var refreshIntervalSeconds: TimeInterval = 60
    var notificationThresholdPercent: Double = 20
    var notificationsEnabled = true
    var launchAtLoginEnabled = false
    var showAPIServices = false
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

extension Date {
    var relativeResetDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    var absoluteDateTimeDescription: String {
        formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(Locale(identifier: "zh_TW"))
        )
    }
}

extension Int64 {
    var compactTokenDescription: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1

        let value = Double(self)
        switch value {
        case 1_000_000_000...:
            return "\(formatter.string(from: NSNumber(value: value / 1_000_000_000)) ?? "0")B"
        case 1_000_000...:
            return "\(formatter.string(from: NSNumber(value: value / 1_000_000)) ?? "0")M"
        case 1_000...:
            return "\(formatter.string(from: NSNumber(value: value / 1_000)) ?? "0")K"
        default:
            return formatter.string(from: NSNumber(value: self)) ?? "0"
        }
    }
}
