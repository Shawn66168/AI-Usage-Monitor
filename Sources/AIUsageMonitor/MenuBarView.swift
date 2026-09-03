import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "gauge.open.with.lines.needle.33percent")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Usage Monitor")
                        .font(.headline)
                    Text(lastUpdateDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(14)

            Divider()

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(store.visibleSnapshots) { snapshot in
                        MenuBarServiceRow(snapshot: snapshot)
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 390)

            Divider()

            HStack(spacing: 8) {
                Button {
                    Task { await store.refreshAll() }
                } label: {
                    Label("更新", systemImage: "arrow.clockwise")
                }
                .disabled(store.isRefreshing)

                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "dashboard")
                } label: {
                    Label("儀表板", systemImage: "macwindow")
                }

                Spacer()

                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help("設定")

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("結束 AI Usage Monitor")
            }
            .buttonStyle(.borderless)
            .padding(12)
        }
        .frame(width: 370)
    }

    private var lastUpdateDescription: String {
        guard let lastRefresh = store.lastRefresh else { return "尚未更新" }
        return "最後更新：\(lastRefresh.formatted(date: .omitted, time: .standard))"
    }
}

private struct MenuBarServiceRow: View {
    let snapshot: AIServiceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: snapshot.id.symbolName)
                    .foregroundStyle(snapshot.id.tint)
                    .frame(width: 20)
                Text(snapshot.id.shortName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let remaining = snapshot.lowestRemainingPercent {
                    Text("\(Int(remaining.rounded()))%")
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(remainingColor(remaining))
                } else {
                    Text(snapshot.status.state.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if snapshot.quotas.isEmpty {
                if let message = snapshot.status.message {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } else {
                ForEach(snapshot.quotas.prefix(2)) { quota in
                    QuotaProgressView(quota: quota, compact: true)
                }
            }
        }
        .padding(11)
        .background(snapshot.id.tint.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(snapshot.id.tint.opacity(0.09), lineWidth: 1)
        }
    }

    private func remainingColor(_ percent: Double) -> Color {
        switch percent {
        case 50 ... 100: .green
        case 20 ..< 50: .orange
        default: .red
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: labelSymbol)
            Text(store.menuBarTitle)
                .monospacedDigit()
        }
        .accessibilityLabel("AI 用量，最低剩餘 \(store.menuBarTitle)")
    }

    private var labelSymbol: String {
        guard let remaining = store.lowestRemainingPercent else {
            return "gauge.open.with.lines.needle.33percent"
        }
        if remaining < store.preferences.notificationThresholdPercent {
            return "exclamationmark.triangle.fill"
        }
        return "gauge.open.with.lines.needle.33percent"
    }
}
