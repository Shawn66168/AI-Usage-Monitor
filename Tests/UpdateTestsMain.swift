import Foundation

@main
struct UpdateTestsMain {
    static func main() async {
        var failures: [String] = []

        testSemanticVersion(failures: &failures)
        testReleasePayload(failures: &failures)
        await testUpdateAvailableAndIgnore(failures: &failures)
        await testETagReuse(failures: &failures)
        await testUpToDateAndPrerelease(failures: &failures)
        testRequestSecurity(failures: &failures)
        testCacheRoundTrip(failures: &failures)

        if failures.isEmpty {
            print("PASS: 7 update test groups")
            exit(0)
        }

        print("FAIL: \(failures.count) issue(s)")
        failures.forEach { print("- \($0)") }
        exit(1)
    }

    private static func testSemanticVersion(failures: inout [String]) {
        expect(SemanticVersion("v1.2.3") == SemanticVersion("1.2.3"), "應忽略版本 v 前綴", failures: &failures)
        expect(SemanticVersion("1.2.3")! < SemanticVersion("1.3.0")!, "minor 版本比較錯誤", failures: &failures)
        expect(SemanticVersion("1.9.9")! < SemanticVersion("2.0.0")!, "major 版本比較錯誤", failures: &failures)
        expect(SemanticVersion("1.0.0-beta.2")! < SemanticVersion("1.0.0-beta.10")!, "數字 prerelease 比較錯誤", failures: &failures)
        expect(SemanticVersion("1.0.0-beta")! < SemanticVersion("1.0.0")!, "正式版應高於 prerelease", failures: &failures)
        expect(SemanticVersion("1.2") == nil, "不完整版本應解析失敗", failures: &failures)
    }

    private static func testReleasePayload(failures: inout [String]) {
        let payload = #"""
        {
          "tag_name": "v0.2.0",
          "name": "AI Usage Monitor v0.2.0",
          "body": "Update notification support",
          "html_url": "https://github.com/Shawn66168/AI-Usage-Monitor/releases/tag/v0.2.0",
          "published_at": "2026-09-04T08:00:00Z",
          "prerelease": false,
          "assets": [
            {
              "name": "AI-Usage-Monitor-macOS-arm64-v0.2.0.zip",
              "browser_download_url": "https://github.com/Shawn66168/AI-Usage-Monitor/releases/download/v0.2.0/app.zip"
            }
          ]
        }
        """#

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let release = try decoder.decode(GitHubReleaseInfo.self, from: Data(payload.utf8))
            expect(release.versionDescription == "0.2.0", "Release version 解碼錯誤", failures: &failures)
            expect(release.appAssetURL != nil, "應辨識 macOS arm64 ZIP", failures: &failures)
            expect(!release.prerelease, "正式版不應標為 prerelease", failures: &failures)
        } catch {
            failures.append("GitHub Release fixture 解碼失敗：\(error.localizedDescription)")
        }
    }

    @MainActor
    private static func testUpdateAvailableAndIgnore(failures: inout [String]) async {
        let environment = TestEnvironment()
        defer { environment.cleanUp() }
        let release = makeRelease(version: "0.2.0")
        let client = StaticReleaseClient(response: .release(release, eTag: "etag-v020"))
        let store = environment.makeStore(currentVersion: "0.1.1", client: client)

        await store.checkNow()
        expect(store.hasAvailableUpdate, "遠端較新時應顯示更新", failures: &failures)
        expect(store.state == .updateAvailable, "狀態應為 updateAvailable", failures: &failures)

        store.ignoreLatestVersion()
        expect(!store.hasAvailableUpdate, "忽略版本後不應提示", failures: &failures)
        expect(store.preferences.ignoredVersion == "0.2.0", "應保存忽略版本", failures: &failures)

        store.clearIgnoredVersion()
        expect(store.hasAvailableUpdate, "清除忽略版本後應恢復提示", failures: &failures)
    }

    @MainActor
    private static func testETagReuse(failures: inout [String]) async {
        let environment = TestEnvironment()
        defer { environment.cleanUp() }
        let client = RecordingReleaseClient(release: makeRelease(version: "0.2.0"))
        let store = environment.makeStore(currentVersion: "0.1.1", client: client)

        await store.checkNow()
        await store.checkNow()
        let values = await client.receivedETags
        expect(values.count == 2, "應執行兩次更新檢查", failures: &failures)
        expect(values[0] == nil, "首次檢查不應附帶 ETag", failures: &failures)
        expect(values[1] == "etag-v020", "後續檢查應重用 ETag", failures: &failures)
        expect(store.hasAvailableUpdate, "304 後應保留更新資訊", failures: &failures)
    }

    @MainActor
    private static func testUpToDateAndPrerelease(failures: inout [String]) async {
        let currentEnvironment = TestEnvironment()
        defer { currentEnvironment.cleanUp() }
        let currentStore = currentEnvironment.makeStore(
            currentVersion: "0.2.0",
            client: StaticReleaseClient(response: .release(makeRelease(version: "0.2.0"), eTag: nil))
        )
        await currentStore.checkNow()
        expect(!currentStore.hasAvailableUpdate, "相同版本不應提示更新", failures: &failures)
        expect(currentStore.state == .upToDate, "相同版本應顯示 upToDate", failures: &failures)

        let prereleaseEnvironment = TestEnvironment()
        defer { prereleaseEnvironment.cleanUp() }
        let prereleaseStore = prereleaseEnvironment.makeStore(
            currentVersion: "0.2.0",
            client: StaticReleaseClient(
                response: .release(makeRelease(version: "0.3.0-beta.1", prerelease: true), eTag: nil)
            )
        )
        await prereleaseStore.checkNow()
        expect(!prereleaseStore.hasAvailableUpdate, "Prerelease 不應提示給正式版使用者", failures: &failures)
    }

    private static func testRequestSecurity(failures: inout [String]) {
        let client = GitHubReleaseClient()
        let request = client.makeRequest(eTag: "public-release-etag")

        expect(
            request.url == GitHubReleaseClient.latestReleaseURL,
            "更新檢查只能連線到固定 GitHub API endpoint",
            failures: &failures
        )
        expect(
            request.value(forHTTPHeaderField: "Authorization") == nil,
            "Public 更新檢查不應附帶 Authorization",
            failures: &failures
        )
        expect(
            request.value(forHTTPHeaderField: "Cookie") == nil,
            "Public 更新檢查不應附帶 Cookie",
            failures: &failures
        )
        expect(
            request.value(forHTTPHeaderField: "If-None-Match") == "public-release-etag",
            "更新檢查應使用 ETag conditional request",
            failures: &failures
        )
        expect(
            GitHubReleaseClient.isTrustedReleaseURL(
                URL(string: "https://github.com/Shawn66168/AI-Usage-Monitor/releases/tag/v0.2.0")!
            ),
            "正確 GitHub Release URL 應通過白名單",
            failures: &failures
        )
        expect(
            !GitHubReleaseClient.isTrustedReleaseURL(
                URL(string: "https://example.invalid/Shawn66168/AI-Usage-Monitor/releases/tag/v9.9.9")!
            ),
            "非 GitHub 網域不應通過白名單",
            failures: &failures
        )
        expect(
            !GitHubReleaseClient.isTrustedReleaseURL(
                URL(string: "http://github.com/Shawn66168/AI-Usage-Monitor/releases/tag/v9.9.9")!
            ),
            "非 HTTPS Release URL 不應通過白名單",
            failures: &failures
        )
    }

    private static func testCacheRoundTrip(failures: inout [String]) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIUsageUpdateCacheTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = root.appendingPathComponent("update-cache.json")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let store = UpdateCacheStore(fileURL: fileURL)
            let cache = UpdateCache(
                release: makeRelease(version: "0.2.0"),
                eTag: "etag-public-metadata",
                lastChecked: Date(timeIntervalSince1970: 1_800_000_000)
            )
            store.save(cache)
            let loaded = store.load()
            expect(loaded?.release.versionDescription == "0.2.0", "Update cache 版本讀回失敗", failures: &failures)
            expect(loaded?.eTag == "etag-public-metadata", "Update cache ETag 讀回失敗", failures: &failures)

            let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            let forbidden = ["authorization", "bearer ", "github_pat_", "csrf", "cookie"]
            expect(
                !forbidden.contains(where: { text.lowercased().contains($0) }),
                "Update cache 不應包含憑證或 Session 資料",
                failures: &failures
            )
        } catch {
            failures.append("Update cache 測試失敗：\(error.localizedDescription)")
        }
        try? FileManager.default.removeItem(at: root)
    }

    private static func makeRelease(version: String, prerelease: Bool = false) -> GitHubReleaseInfo {
        GitHubReleaseInfo(
            tagName: "v\(version)",
            name: "AI Usage Monitor v\(version)",
            body: "Release notes for \(version)",
            htmlURL: URL(string: "https://github.com/Shawn66168/AI-Usage-Monitor/releases/tag/v\(version)")!,
            publishedAt: Date(timeIntervalSince1970: 1_800_000_000),
            prerelease: prerelease,
            appAssetURL: URL(string: "https://github.com/Shawn66168/AI-Usage-Monitor/releases/download/v\(version)/app.zip")
        )
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String,
        failures: inout [String]
    ) {
        if !condition() {
            failures.append(message)
        }
    }
}

private struct StaticReleaseClient: GitHubReleaseFetching {
    let response: UpdateCheckResponse

    func fetchLatestRelease(eTag: String?) async throws -> UpdateCheckResponse {
        response
    }
}

private actor RecordingReleaseClient: GitHubReleaseFetching {
    private let release: GitHubReleaseInfo
    private(set) var receivedETags: [String?] = []

    init(release: GitHubReleaseInfo) {
        self.release = release
    }

    func fetchLatestRelease(eTag: String?) async throws -> UpdateCheckResponse {
        receivedETags.append(eTag)
        if eTag == nil {
            return .release(release, eTag: "etag-v020")
        }
        return .notModified
    }
}

@MainActor
private final class TestEnvironment {
    private let root: URL
    private let defaults: UserDefaults
    private let preferencesKey: String

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIUsageUpdateStoreTests-\(UUID().uuidString)", isDirectory: true)
        preferencesKey = "AIUsageMonitor.updateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: preferencesKey)!
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func makeStore(
        currentVersion: String,
        client: any GitHubReleaseFetching
    ) -> AppUpdateStore {
        AppUpdateStore(
            currentVersionString: currentVersion,
            client: client,
            cacheStore: UpdateCacheStore(fileURL: root.appendingPathComponent("cache.json")),
            preferencesStore: UpdatePreferencesStore(key: preferencesKey, defaults: defaults)
        )
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: preferencesKey)
        try? FileManager.default.removeItem(at: root)
    }
}
