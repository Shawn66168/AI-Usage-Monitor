import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedService) {
                Section("總覽") {
                    Label("所有服務", systemImage: "square.grid.2x2.fill")
                        .tag(ServiceKind?.none)
                }

                Section("AI 服務") {
                    ForEach(store.visibleSnapshots) { snapshot in
                        SidebarServiceRow(snapshot: snapshot)
                            .tag(Optional(snapshot.id))
                    }
                }
            }
            .navigationTitle("AI 用量")
            .navigationSplitViewColumnWidth(min: 210, ideal: 235)
        } detail: {
            if let selectedService = store.selectedService,
               let snapshot = store.snapshot(for: selectedService) {
                ServiceDetailView(snapshot: snapshot)
            } else {
                OverviewDashboardView(store: store)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                if let lastRefresh = store.lastRefresh {
                    Text("更新於 \(lastRefresh.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await store.refreshAll() }
                } label: {
                    if store.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("立即更新", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(store.isRefreshing)
                .help("立即更新所有用量資料")

                SettingsLink {
                    Label("設定", systemImage: "gearshape")
                }
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .background(DashboardBackground())
    }
}

private struct SidebarServiceRow: View {
    let snapshot: AIServiceSnapshot

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: snapshot.id.symbolName)
                .foregroundStyle(snapshot.id.tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.id.shortName)
                    .lineLimit(1)
                if let remaining = snapshot.lowestRemainingPercent {
                    Text("剩餘 \(Int(remaining.rounded()))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(remaining < 20 ? .red : .secondary)
                } else {
                    Text(snapshot.status.state.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
        }
        .padding(.vertical, 3)
    }

    private var statusColor: Color {
        switch snapshot.status.state {
        case .available: .green
        case .stale: .orange
        case .loading: .blue
        case .error: .red
        default: .secondary.opacity(0.55)
        }
    }
}

private struct OverviewDashboardView: View {
    @ObservedObject var store: UsageStore

    private let columns = [
        GridItem(.adaptive(minimum: 330, maximum: 520), spacing: 18)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                overviewHeader
                summaryStrip

                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(store.visibleSnapshots) { snapshot in
                        ServiceCardView(snapshot: snapshot)
                    }
                }
            }
            .padding(26)
        }
        .navigationTitle("AI 用量總覽")
    }

    private var overviewHeader: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("AI Usage Monitor")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("集中掌握剩餘額度、Token、Context 與下一次重置時間")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.isRefreshing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在同步本機資料")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 12) {
            SummaryMetricCard(
                title: "服務數",
                value: "\(store.visibleSnapshots.count)",
                subtitle: "集中監控",
                symbol: "square.grid.2x2.fill",
                tint: .blue
            )
            SummaryMetricCard(
                title: "最低剩餘",
                value: store.lowestRemainingPercent.map { "\(Int($0.rounded()))%" } ?? "—",
                subtitle: lowestRemainingSubtitle,
                symbol: "gauge.with.dots.needle.33percent",
                tint: lowestRemainingTint
            )
            SummaryMetricCard(
                title: "可用資料源",
                value: "\(availableCount)",
                subtitle: "即時或快取",
                symbol: "checkmark.seal.fill",
                tint: .green
            )
            SummaryMetricCard(
                title: "更新頻率",
                value: "\(Int(store.preferences.refreshIntervalSeconds)) 秒",
                subtitle: "可於設定調整",
                symbol: "clock.arrow.2.circlepath",
                tint: .purple
            )
        }
    }

    private var availableCount: Int {
        store.visibleSnapshots.filter {
            [.available, .stale].contains($0.status.state)
        }.count
    }

    private var lowestRemainingSubtitle: String {
        guard let value = store.lowestRemainingPercent else { return "等待資料" }
        if value < store.preferences.notificationThresholdPercent { return "低於警示門檻" }
        return "目前狀態正常"
    }

    private var lowestRemainingTint: Color {
        guard let value = store.lowestRemainingPercent else { return .secondary }
        switch value {
        case 50 ... 100: return Color.green
        case 20 ..< 50: return Color.orange
        default: return Color.red
        }
    }
}

private struct SummaryMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.monospacedDigit().weight(.bold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
        }
        .padding(13)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15))
    }
}

private struct ServiceDetailView: View {
    let snapshot: AIServiceSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: snapshot.id.symbolName)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(snapshot.id.tint.gradient, in: RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.displayName)
                            .font(.largeTitle.bold())
                        Text(snapshot.sourceDescription)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(status: snapshot.status)
                }

                ServiceCardView(snapshot: snapshot)

                GroupBox("資料說明") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("所有數值只在此 Mac 上處理。應用程式只讀取 quota 與 token_count 等非對話欄位，不讀取 Prompt 或回覆文字。")
                        if let message = snapshot.status.message {
                            Text(message)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                }
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .navigationTitle(snapshot.id.shortName)
    }
}

private struct DashboardBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color.blue.opacity(0.035),
                Color.purple.opacity(0.025)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
