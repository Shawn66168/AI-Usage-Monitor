import Foundation

@main
struct LiveUpdateCheckMain {
    @MainActor
    static func main() async {
        let currentVersion = CommandLine.arguments.dropFirst().first ?? "0.0.0"
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIUsageLiveUpdateCheck-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "AIUsageMonitor.liveUpdateCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: root)
        }

        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let store = AppUpdateStore(
                currentVersionString: currentVersion,
                client: GitHubReleaseClient(),
                cacheStore: UpdateCacheStore(fileURL: root.appendingPathComponent("cache.json")),
                preferencesStore: UpdatePreferencesStore(
                    key: "update-preferences",
                    defaults: defaults
                )
            )
            await store.checkNow(ignoreETag: true)

            guard let release = store.latestRelease,
                  release.htmlURL.host == "github.com",
                  release.semanticVersion != nil else {
                print("FAIL: \(store.statusDescription)")
                exit(1)
            }

            let summary: [String: Any] = [
                "passed": true,
                "currentVersion": currentVersion,
                "latestVersion": release.versionDescription,
                "updateAvailable": store.hasAvailableUpdate,
                "releaseHost": release.htmlURL.host ?? ""
            ]
            let data = try JSONSerialization.data(
                withJSONObject: summary,
                options: [.prettyPrinted, .sortedKeys]
            )
            print(String(decoding: data, as: UTF8.self))
        } catch {
            print("FAIL: \(error.localizedDescription)")
            exit(1)
        }
    }
}
