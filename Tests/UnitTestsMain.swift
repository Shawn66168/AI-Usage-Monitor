import Foundation

@main
struct UnitTestsMain {
    static func main() async {
        var failures: [String] = []

        testQuotaNormalization(failures: &failures)
        testDateParsing(failures: &failures)
        await testClaudeFixture(failures: &failures)
        await testProcessRunner(failures: &failures)
        testKeychainRoundTrip(failures: &failures)
        testProviderRefreshGate(failures: &failures)

        if failures.isEmpty {
            print("PASS: 6 test groups")
            exit(0)
        }

        print("FAIL: \(failures.count) issue(s)")
        failures.forEach { print("- \($0)") }
        exit(1)
    }

    private static func testQuotaNormalization(failures: inout [String]) {
        let over = QuotaWindow(
            id: "over",
            label: "Over",
            usedPercent: 125,
            scope: .weekly
        )
        expect(over.usedPercent == 100, "usedPercent 應限制於 100", failures: &failures)
        expect(over.remainingPercent == 0, "remainingPercent 應限制於 0", failures: &failures)

        let under = QuotaWindow(
            id: "under",
            label: "Under",
            remainingPercent: -20,
            scope: .rolling
        )
        expect(under.remainingPercent == 0, "負的剩餘百分比應限制於 0", failures: &failures)
        expect(under.usedPercent == 100, "負的剩餘百分比應換算為 100% 已用", failures: &failures)
    }

    private static func testDateParsing(failures: inout [String]) {
        expect(
            FlexibleDateParser.parse("2026-09-04T10:15:30.123Z") != nil,
            "應解析含毫秒 ISO 8601 日期",
            failures: &failures
        )
        expect(
            FlexibleDateParser.parse("2026-09-04T10:15:30Z") != nil,
            "應解析標準 ISO 8601 日期",
            failures: &failures
        )
    }

    private static func testClaudeFixture(failures: inout [String]) async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIUsageMonitorTests-\(UUID().uuidString)", isDirectory: true)
        let claudeDirectory = root.appendingPathComponent(".claude", isDirectory: true)
        let fileURL = claudeDirectory.appendingPathComponent("usage-status.json")

        do {
            try FileManager.default.createDirectory(
                at: claudeDirectory,
                withIntermediateDirectories: true
            )
            let fixture = #"""
            {
              "model":{"id":"claude-test","display_name":"Claude Test"},
              "context_window":{
                "total_input_tokens":1200,
                "total_output_tokens":300,
                "context_window_size":10000,
                "current_usage":{
                  "input_tokens":200,
                  "output_tokens":300,
                  "cache_creation_input_tokens":100,
                  "cache_read_input_tokens":900
                },
                "used_percentage":15
              },
              "cost":{"total_cost_usd":1.25},
              "rate_limits":{
                "five_hour":{"used_percentage":27,"resets_at":1893456000},
                "seven_day":{"used_percentage":64,"resets_at":1893888000}
              }
            }
            """#
            try Data(fixture.utf8).write(to: fileURL)

            let snapshot = await ClaudeProvider(homeDirectory: root).fetchSnapshot()
            expect(snapshot.status.state == .available, "Claude fixture 應成功解析", failures: &failures)
            expect(snapshot.quotas.count == 2, "Claude fixture 應有兩個 quota window", failures: &failures)
            expect(snapshot.quotas.first?.remainingPercent == 73, "5 小時剩餘應為 73%", failures: &failures)
            expect(snapshot.tokenUsage?.totalTokens == 1500, "Claude 總 Token 應為 1,500", failures: &failures)
            expect(snapshot.contextUsage?.usedPercent == 15, "Claude Context 應為 15%", failures: &failures)
            expect(snapshot.contextUsage?.remainingTokens == 8500, "Claude Context 剩餘應為 8,500", failures: &failures)
            expect(snapshot.costUsage?.amountUSD == 1.25, "Claude session cost 應為 USD 1.25", failures: &failures)
        } catch {
            failures.append("Claude fixture 建立失敗：\(error.localizedDescription)")
        }

        try? FileManager.default.removeItem(at: root)
    }

    private static func testProcessRunner(failures: inout [String]) async {
        do {
            let result = try await ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/echo"),
                arguments: ["ai-usage-monitor-test"],
                timeout: 3
            )
            expect(result.exitCode == 0, "ProcessRunner exit code 應為 0", failures: &failures)
            expect(
                result.standardOutput.contains("ai-usage-monitor-test"),
                "ProcessRunner 應完整讀取 stdout",
                failures: &failures
            )
        } catch {
            failures.append("ProcessRunner 測試失敗：\(error.localizedDescription)")
        }
    }

    private static func testKeychainRoundTrip(failures: inout [String]) {
        let keychain = KeychainStore(service: "com.xing.ai-usage-monitor.tests.\(UUID().uuidString)")
        do {
            try keychain.save("diagnostic-value", for: .openAIAdminKey)
            expect(
                try keychain.read(.openAIAdminKey) == "diagnostic-value",
                "Keychain 應能讀回測試資料",
                failures: &failures
            )
            try keychain.delete(.openAIAdminKey)
            expect(
                try keychain.read(.openAIAdminKey) == nil,
                "Keychain 刪除後不應殘留測試資料",
                failures: &failures
            )
        } catch {
            failures.append("Keychain 測試失敗：\(error.localizedDescription)")
        }
    }

    private static func testProviderRefreshGate(failures: inout [String]) {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var gate = ProviderRefreshGate()

        expect(
            ProviderRefreshInterval.adminAPI == 15 * 60,
            "Admin API 最小刷新間隔應為 15 分鐘",
            failures: &failures
        )
        expect(
            AnthropicAdminProvider().minimumRefreshInterval == 15 * 60,
            "Anthropic Admin Provider 應採 15 分鐘刷新間隔",
            failures: &failures
        )
        expect(
            OpenAIAdminProvider().minimumRefreshInterval == 15 * 60,
            "OpenAI Admin Provider 應採 15 分鐘刷新間隔",
            failures: &failures
        )
        expect(
            gate.shouldRefresh(
                .anthropicAPI,
                minimumInterval: ProviderRefreshInterval.adminAPI,
                at: start
            ),
            "Anthropic Admin API 首次刷新應允許",
            failures: &failures
        )
        expect(
            !gate.shouldRefresh(
                .anthropicAPI,
                minimumInterval: ProviderRefreshInterval.adminAPI,
                at: start.addingTimeInterval(899)
            ),
            "Anthropic Admin API 在 15 分鐘前不應再次刷新",
            failures: &failures
        )
        expect(
            gate.nextAllowedAt(
                for: .anthropicAPI,
                minimumInterval: ProviderRefreshInterval.adminAPI
            ) == start.addingTimeInterval(900),
            "Anthropic Admin API 下一次允許時間應為 15 分鐘後",
            failures: &failures
        )
        expect(
            gate.shouldRefresh(
                .anthropicAPI,
                minimumInterval: ProviderRefreshInterval.adminAPI,
                at: start.addingTimeInterval(900)
            ),
            "Anthropic Admin API 到 15 分鐘時應允許刷新",
            failures: &failures
        )
        expect(
            gate.shouldRefresh(
                .openAIAPI,
                minimumInterval: ProviderRefreshInterval.adminAPI,
                at: start
            ),
            "OpenAI Admin API 應使用獨立刷新閘門",
            failures: &failures
        )

        var forcedGate = ProviderRefreshGate()
        _ = forcedGate.shouldRefresh(
            .openAIAPI,
            minimumInterval: ProviderRefreshInterval.adminAPI,
            at: start
        )
        expect(
            forcedGate.shouldRefresh(
                .openAIAPI,
                minimumInterval: ProviderRefreshInterval.adminAPI,
                at: start.addingTimeInterval(60),
                force: true
            ),
            "管理憑證變更後應允許強制刷新對應 API",
            failures: &failures
        )

        var localGate = ProviderRefreshGate()
        expect(
            localGate.shouldRefresh(.claude, minimumInterval: 0, at: start)
                && localGate.shouldRefresh(.claude, minimumInterval: 0, at: start),
            "本機 Provider 應維持每輪刷新",
            failures: &failures
        )
    }

    private static func expect(
        _ condition: @autoclosure () throws -> Bool,
        _ message: String,
        failures: inout [String]
    ) {
        do {
            if try !condition() {
                failures.append(message)
            }
        } catch {
            failures.append("\(message)：\(error.localizedDescription)")
        }
    }
}
