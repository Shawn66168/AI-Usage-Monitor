import Foundation
import ServiceManagement
import UserNotifications

@MainActor
final class UsageNotificationManager {
    private let defaultsKey = "AIUsageMonitor.notifiedQuotaKeys.v1"

    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    func requestAuthorizationIfNeeded() async {
        guard let center else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func evaluate(
        snapshots: [AIServiceSnapshot],
        threshold: Double,
        enabled: Bool
    ) async {
        guard enabled, let center else { return }
        await requestAuthorizationIfNeeded()

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else {
            return
        }

        var notifiedKeys = Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
        let now = Date()

        for snapshot in snapshots where snapshot.status.state == .available || snapshot.status.state == .stale {
            for quota in snapshot.quotas where quota.remainingPercent <= threshold {
                let resetComponent = quota.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "unknown"
                let key = "\(snapshot.id.rawValue)|\(quota.id)|\(resetComponent)"
                guard !notifiedKeys.contains(key) else { continue }

                let content = UNMutableNotificationContent()
                content.title = "\(snapshot.id.shortName) 用量提醒"
                content.body = notificationBody(snapshot: snapshot, quota: quota)
                content.sound = .default

                let request = UNNotificationRequest(
                    identifier: "ai-usage-monitor-\(abs(key.hashValue))",
                    content: content,
                    trigger: nil
                )

                do {
                    try await center.add(request)
                    notifiedKeys.insert(key)
                } catch {
                    continue
                }
            }
        }

        let activePrefixes = Set(
            snapshots.flatMap { snapshot in
                snapshot.quotas.map { quota in
                    "\(snapshot.id.rawValue)|\(quota.id)|"
                }
            }
        )
        notifiedKeys = Set(notifiedKeys.filter { key in
            activePrefixes.contains { key.hasPrefix($0) }
                || !key.contains("|unknown")
        })

        UserDefaults.standard.set(Array(notifiedKeys).sorted(), forKey: defaultsKey)

        if notifiedKeys.count > 200 {
            UserDefaults.standard.set(Array(notifiedKeys.suffix(100)), forKey: defaultsKey)
        }

        _ = now
    }

    private func notificationBody(snapshot: AIServiceSnapshot, quota: QuotaWindow) -> String {
        var parts = [
            "\(quota.label)僅剩 \(Int(quota.remainingPercent.rounded()))%"
        ]
        if let resetsAt = quota.resetsAt {
            parts.append("將於 \(resetsAt.absoluteDateTimeDescription) 重置")
        }
        return parts.joined(separator: "，")
    }
}

@MainActor
final class LaunchAtLoginManager {
    var isRegistered: Bool {
        switch SMAppService.mainApp.status {
        case .enabled:
            true
        default:
            false
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard SMAppService.mainApp.status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard SMAppService.mainApp.status == .enabled
                    || SMAppService.mainApp.status == .requiresApproval else {
                return
            }
            try SMAppService.mainApp.unregister()
        }
    }

    var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            "未註冊"
        case .enabled:
            "已啟用"
        case .requiresApproval:
            "等待你在「系統設定 → 一般 → 登入項目」核准"
        case .notFound:
            "找不到應用程式 bundle；請先使用打包後的 .app"
        @unknown default:
            "未知狀態"
        }
    }
}
