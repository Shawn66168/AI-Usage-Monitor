import Foundation
import SwiftUI

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshots: [AIServiceSnapshot]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    @Published var selectedService: ServiceKind?
    @Published var preferences: AppPreferences {
        didSet {
            preferencesStore.save(preferences)
            restartAutoRefreshIfNeeded()
        }
    }

    private let providers: [any UsageProvider]
    private let snapshotCache: SnapshotCache
    private let preferencesStore: PreferencesStore
    private let notificationManager: UsageNotificationManager
    private var refreshTask: Task<Void, Never>?
    private var autoRefreshStarted = false

    init(
        providers: [any UsageProvider],
        snapshotCache: SnapshotCache = SnapshotCache(),
        preferencesStore: PreferencesStore = PreferencesStore(),
        notificationManager: UsageNotificationManager = UsageNotificationManager()
    ) {
        self.providers = providers
        self.snapshotCache = snapshotCache
        self.preferencesStore = preferencesStore
        self.notificationManager = notificationManager
        self.preferences = preferencesStore.load()

        let cached = snapshotCache.load()
        let cachedByKind = Dictionary(uniqueKeysWithValues: cached.map { ($0.id, $0) })
        self.snapshots = ServiceKind.allCases.map { kind in
            if var snapshot = cachedByKind[kind] {
                snapshot.status = ProviderStatus(
                    state: .stale,
                    message: "顯示上次成功更新的本機快取"
                )
                return snapshot
            }
            return .placeholder(
                for: kind,
                status: ProviderStatus(state: .loading, message: "準備讀取用量資料"),
                source: "尚未取得資料"
            )
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    var visibleSnapshots: [AIServiceSnapshot] {
        snapshots.filter { snapshot in
            preferences.showAPIServices || ![ServiceKind.anthropicAPI, .openAIAPI].contains(snapshot.id)
        }
    }

    var lowestRemainingPercent: Double? {
        visibleSnapshots.compactMap(\.lowestRemainingPercent).min()
    }

    var menuBarTitle: String {
        guard let lowestRemainingPercent else { return "AI" }
        return "\(Int(lowestRemainingPercent.rounded()))%"
    }

    func start() {
        guard !autoRefreshStarted else { return }
        autoRefreshStarted = true
        startAutoRefreshLoop()
    }

    func stop() {
        autoRefreshStarted = false
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let providers = self.providers
        var fetched: [AIServiceSnapshot] = []

        await withTaskGroup(of: AIServiceSnapshot.self) { group in
            for provider in providers {
                group.addTask {
                    await provider.fetchSnapshot()
                }
            }

            for await snapshot in group {
                fetched.append(snapshot)
            }
        }

        let currentByKind = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
        let fetchedByKind = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })

        snapshots = ServiceKind.allCases.map { kind in
            guard let next = fetchedByKind[kind] else {
                return currentByKind[kind] ?? .placeholder(
                    for: kind,
                    status: .unavailable("尚未建立資料來源"),
                    source: "無"
                )
            }

            if next.status.state == .available || next.status.state == .unsupported || next.status.state == .needsConfiguration {
                return next
            }

            if var previous = currentByKind[kind], !previous.quotas.isEmpty || previous.tokenUsage != nil {
                previous.status = ProviderStatus(
                    state: .stale,
                    message: next.status.message ?? "暫時無法更新，顯示最近資料"
                )
                return previous
            }

            return next
        }

        lastRefresh = Date()
        snapshotCache.save(snapshots.filter { snapshot in
            snapshot.status.state == .available || !snapshot.quotas.isEmpty || snapshot.tokenUsage != nil
        })

        await notificationManager.evaluate(
            snapshots: snapshots,
            threshold: preferences.notificationThresholdPercent,
            enabled: preferences.notificationsEnabled
        )
    }

    func snapshot(for kind: ServiceKind) -> AIServiceSnapshot? {
        snapshots.first { $0.id == kind }
    }

    private func restartAutoRefreshIfNeeded() {
        guard autoRefreshStarted else { return }
        refreshTask?.cancel()
        startAutoRefreshLoop()
    }

    private func startAutoRefreshLoop() {
        refreshTask = Task { [weak self] in
            guard let self else { return }

            await self.refreshAll()

            while !Task.isCancelled {
                let interval = max(30, self.preferences.refreshIntervalSeconds)
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }
                await self.refreshAll()
            }
        }
    }
}

struct SnapshotCache {
    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        let supportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser

        let directory = supportURL.appendingPathComponent(
            "AIUsageMonitor",
            isDirectory: true
        )
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        self.fileURL = directory.appendingPathComponent("snapshots.json")
    }

    func load() -> [AIServiceSnapshot] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([AIServiceSnapshot].self, from: data)) ?? []
    }

    func save(_ snapshots: [AIServiceSnapshot]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(snapshots) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}

struct PreferencesStore {
    private let key = "AIUsageMonitor.preferences.v1"

    func load() -> AppPreferences {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let preferences = try? JSONDecoder().decode(AppPreferences.self, from: data)
        else {
            return AppPreferences()
        }
        return preferences
    }

    func save(_ preferences: AppPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
