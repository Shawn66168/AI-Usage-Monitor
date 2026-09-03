import SwiftUI

struct StatusBadge: View {
    let status: ProviderStatus

    private var color: Color {
        switch status.state {
        case .available: .green
        case .stale: .orange
        case .loading: .blue
        case .unavailable: .secondary
        case .unsupported: .secondary
        case .needsConfiguration: .purple
        case .error: .red
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(status.state.label)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct QuotaProgressView: View {
    let quota: QuotaWindow
    var compact = false

    private var progressColor: Color {
        switch quota.remainingPercent {
        case 50 ... 100: .green
        case 20 ..< 50: .orange
        default: .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(quota.label)
                    .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text("剩餘 \(Int(quota.remainingPercent.rounded()))%")
                    .font(compact ? .caption2.monospacedDigit() : .subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(progressColor)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.16))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [progressColor.opacity(0.72), progressColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * quota.remainingPercent / 100)
                }
            }
            .frame(height: compact ? 6 : 8)

            HStack(spacing: 6) {
                Text("已用 \(Int(quota.usedPercent.rounded()))%")
                if let resetsAt = quota.resetsAt {
                    Text("·")
                    Text("\(resetsAt.relativeResetDescription)重置")
                        .help(resetsAt.absoluteDateTimeDescription)
                }
                Spacer()
                if let detail = quota.detail, !detail.isEmpty {
                    Text(detail)
                        .lineLimit(1)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(quota.label)，剩餘 \(Int(quota.remainingPercent.rounded()))%，已用 \(Int(quota.usedPercent.rounded()))%")
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    var detail: String? = nil
    var symbol: String
    var tint: Color

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct TokenSummaryView: View {
    let usage: TokenUsage
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Token", systemImage: "number.square.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(usage.periodLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                MetricTile(
                    title: "總量",
                    value: usage.totalTokens.compactTokenDescription,
                    symbol: "sum",
                    tint: tint
                )
                MetricTile(
                    title: "輸入",
                    value: usage.inputTokens.compactTokenDescription,
                    symbol: "arrow.down.left",
                    tint: .blue
                )
                MetricTile(
                    title: "輸出",
                    value: usage.outputTokens.compactTokenDescription,
                    symbol: "arrow.up.right",
                    tint: .purple
                )
                MetricTile(
                    title: "快取讀取",
                    value: usage.cachedInputTokens.compactTokenDescription,
                    symbol: "bolt.horizontal.circle",
                    tint: .orange
                )
            }
        }
    }
}

struct ContextSummaryView: View {
    let usage: ContextUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Context", systemImage: "rectangle.stack.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(usage.usedPercent.rounded()))%")
                    .font(.subheadline.monospacedDigit().weight(.bold))
            }

            ProgressView(value: usage.usedPercent, total: 100)
                .tint(usage.usedPercent >= 85 ? .red : usage.usedPercent >= 65 ? .orange : .blue)

            HStack {
                Text("已用 \(usage.usedTokens.compactTokenDescription)")
                Text("·")
                Text("剩餘 \(usage.remainingTokens.compactTokenDescription)")
                Spacer()
                Text("上限 \(usage.windowTokens.compactTokenDescription)")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
    }
}

struct EmptyServiceStateView: View {
    let snapshot: AIServiceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(snapshot.status.state.label, systemImage: emptySymbol)
                .font(.subheadline.weight(.semibold))
            if let message = snapshot.status.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var emptySymbol: String {
        switch snapshot.status.state {
        case .unsupported: "nosign"
        case .needsConfiguration: "key.fill"
        case .unavailable: "power"
        case .error: "exclamationmark.triangle.fill"
        case .loading: "arrow.triangle.2.circlepath"
        default: "info.circle.fill"
        }
    }
}

struct ServiceCardView: View {
    let snapshot: AIServiceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: snapshot.id.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(snapshot.id.tint.gradient, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.displayName)
                        .font(.headline)
                    Text(snapshot.planName ?? snapshot.sourceDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
                StatusBadge(status: snapshot.status)
            }

            if snapshot.quotas.isEmpty, snapshot.tokenUsage == nil, snapshot.contextUsage == nil {
                EmptyServiceStateView(snapshot: snapshot)
            } else {
                ForEach(snapshot.quotas) { quota in
                    QuotaProgressView(quota: quota)
                }

                if let context = snapshot.contextUsage {
                    ContextSummaryView(usage: context)
                }

                if let tokens = snapshot.tokenUsage {
                    TokenSummaryView(usage: tokens, tint: snapshot.id.tint)
                }

                if let cost = snapshot.costUsage {
                    MetricTile(
                        title: cost.periodLabel,
                        value: cost.amountUSD.formatted(.currency(code: "USD")),
                        detail: "官方 API 組織費用彙總",
                        symbol: "dollarsign.circle.fill",
                        tint: snapshot.id.tint
                    )
                }
            }

            HStack {
                Label(snapshot.sourceDescription, systemImage: "externaldrive.fill")
                    .lineLimit(1)
                Spacer()
                Text(snapshot.fetchedAt, style: .relative)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(snapshot.id.tint.opacity(0.12), lineWidth: 1)
        }
    }
}
