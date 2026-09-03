import Foundation

@main
struct DiagnosticsMain {
    static func main() async {
        let providers: [any UsageProvider] = [
            ClaudeProvider(),
            CodexProvider(),
            AntigravityProvider(),
            UnsupportedProvider(
                kind: .chatGPT,
                reason: "官方未提供",
                sourceDescription: "官方未提供"
            ),
            UnsupportedProvider(
                kind: .manus,
                reason: "等待官方資料來源",
                sourceDescription: "官方資料來源待確認"
            ),
            AnthropicAdminProvider(),
            OpenAIAdminProvider()
        ]

        var snapshots: [AIServiceSnapshot] = []
        var failures: [String] = []

        let start = Date()
        await withTaskGroup(of: AIServiceSnapshot.self) { group in
            for provider in providers {
                group.addTask {
                    await provider.fetchSnapshot()
                }
            }
            for await snapshot in group {
                snapshots.append(snapshot)
            }
        }
        let elapsed = Date().timeIntervalSince(start)

        let byKind = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
        for kind in ServiceKind.allCases where byKind[kind] == nil {
            failures.append("缺少 \(kind.rawValue) snapshot")
        }

        for snapshot in snapshots {
            for quota in snapshot.quotas {
                if !(0 ... 100).contains(quota.usedPercent) {
                    failures.append("\(snapshot.id.rawValue)/\(quota.id) usedPercent 超出範圍")
                }
                if !(0 ... 100).contains(quota.remainingPercent) {
                    failures.append("\(snapshot.id.rawValue)/\(quota.id) remainingPercent 超出範圍")
                }
                if abs((quota.usedPercent + quota.remainingPercent) - 100) > 0.01 {
                    failures.append("\(snapshot.id.rawValue)/\(quota.id) used + remaining 不等於 100")
                }
            }

            if let tokens = snapshot.tokenUsage {
                let values = [
                    tokens.inputTokens,
                    tokens.cachedInputTokens,
                    tokens.cacheWriteInputTokens,
                    tokens.outputTokens,
                    tokens.reasoningOutputTokens,
                    tokens.totalTokens
                ]
                if values.contains(where: { $0 < 0 }) {
                    failures.append("\(snapshot.id.rawValue) Token 出現負值")
                }
            }

            if let context = snapshot.contextUsage {
                if context.usedTokens < 0 || context.windowTokens < 0 {
                    failures.append("\(snapshot.id.rawValue) Context 出現負值")
                }
                if !(0 ... 100).contains(context.usedPercent) {
                    failures.append("\(snapshot.id.rawValue) Context 百分比超出範圍")
                }
            }

            let privacySurface = [
                snapshot.sourceDescription,
                snapshot.status.message ?? "",
                snapshot.planName ?? ""
            ].joined(separator: " ").lowercased()
            let forbiddenMarkers = ["bearer ", "csrf_token=", "authorization:"]
            if forbiddenMarkers.contains(where: privacySurface.contains) {
                failures.append("\(snapshot.id.rawValue) 顯示資料疑似包含敏感憑證")
            }
        }

        if elapsed > 30 {
            failures.append("Provider 全量刷新耗時超過 30 秒：\(elapsed)")
        }

        let report = DiagnosticReport(
            passed: failures.isEmpty,
            elapsedSeconds: elapsed,
            failures: failures,
            services: snapshots.sorted { $0.id.rawValue < $1.id.rawValue }.map {
                DiagnosticService(
                    id: $0.id.rawValue,
                    state: $0.status.state.rawValue,
                    quotaCount: $0.quotas.count,
                    hasTokenUsage: $0.tokenUsage != nil,
                    hasContextUsage: $0.contextUsage != nil,
                    source: $0.sourceDescription
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report), let text = String(data: data, encoding: .utf8) {
            print(text)
        }

        if !failures.isEmpty {
            exit(1)
        }
    }
}

private struct DiagnosticReport: Encodable {
    let passed: Bool
    let elapsedSeconds: TimeInterval
    let failures: [String]
    let services: [DiagnosticService]
}

private struct DiagnosticService: Encodable {
    let id: String
    let state: String
    let quotaCount: Int
    let hasTokenUsage: Bool
    let hasContextUsage: Bool
    let source: String
}
