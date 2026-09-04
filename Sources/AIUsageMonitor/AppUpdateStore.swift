import Foundation

struct SemanticVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: [Identifier]

    enum Identifier: Equatable, Sendable {
        case numeric(Int)
        case text(String)
    }

    init?(_ rawValue: String) {
        var normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.lowercased().hasPrefix("v") {
            normalized.removeFirst()
        }
        normalized = normalized.split(separator: "+", maxSplits: 1).first.map(String.init) ?? normalized

        let versionAndPrerelease = normalized.split(
            separator: "-",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let components = versionAndPrerelease[0].split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2]),
              major >= 0, minor >= 0, patch >= 0 else {
            return nil
        }

        self.major = major
        self.minor = minor
        self.patch = patch

        if versionAndPrerelease.count == 2, !versionAndPrerelease[1].isEmpty {
            let parsed = versionAndPrerelease[1].split(separator: ".").map { value -> Identifier in
                if let number = Int(value) {
                    return .numeric(number)
                }
                return .text(String(value).lowercased())
            }
            prerelease = parsed
        } else {
            prerelease = []
        }
    }

    var description: String {
        var value = "\(major).\(minor).\(patch)"
        if !prerelease.isEmpty {
            let suffix = prerelease.map { identifier in
                switch identifier {
                case let .numeric(number): String(number)
                case let .text(text): text
                }
            }.joined(separator: ".")
            value += "-\(suffix)"
        }
        return value
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let lhsCore = [lhs.major, lhs.minor, lhs.patch]
        let rhsCore = [rhs.major, rhs.minor, rhs.patch]
        if lhsCore != rhsCore {
            return lhsCore.lexicographicallyPrecedes(rhsCore)
        }

        if lhs.prerelease.isEmpty != rhs.prerelease.isEmpty {
            return !lhs.prerelease.isEmpty
        }

        for index in 0 ..< min(lhs.prerelease.count, rhs.prerelease.count) {
            let left = lhs.prerelease[index]
            let right = rhs.prerelease[index]
            guard left != right else { continue }

            switch (left, right) {
            case let (.numeric(lhsNumber), .numeric(rhsNumber)):
                return lhsNumber < rhsNumber
            case (.numeric, .text):
                return true
            case (.text, .numeric):
                return false
            case let (.text(lhsText), .text(rhsText)):
                return lhsText < rhsText
            }
        }

        return lhs.prerelease.count < rhs.prerelease.count
    }
}

struct GitHubReleaseInfo: Codable, Equatable, Sendable {
    let tagName: String
    let name: String
    let body: String
    let htmlURL: URL
    let publishedAt: Date?
    let prerelease: Bool
    let appAssetURL: URL?

    var semanticVersion: SemanticVersion? {
        SemanticVersion(tagName)
    }

    var versionDescription: String {
        semanticVersion?.description ?? tagName
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case prerelease
        case assets
        case appAssetURL
    }

    private struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    init(
        tagName: String,
        name: String,
        body: String,
        htmlURL: URL,
        publishedAt: Date?,
        prerelease: Bool,
        appAssetURL: URL?
    ) {
        self.tagName = tagName
        self.name = name
        self.body = body
        self.htmlURL = htmlURL
        self.publishedAt = publishedAt
        self.prerelease = prerelease
        self.appAssetURL = appAssetURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? tagName
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        htmlURL = try container.decode(URL.self, forKey: .htmlURL)
        publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
        prerelease = try container.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false

        if let cachedAssetURL = try container.decodeIfPresent(URL.self, forKey: .appAssetURL) {
            appAssetURL = cachedAssetURL
        } else {
            let assets = try container.decodeIfPresent([Asset].self, forKey: .assets) ?? []
            appAssetURL = assets.first { asset in
                let name = asset.name.lowercased()
                return name.hasSuffix(".zip")
                    && name.contains("macos")
                    && name.contains("arm64")
            }?.browserDownloadURL
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tagName, forKey: .tagName)
        try container.encode(name, forKey: .name)
        try container.encode(body, forKey: .body)
        try container.encode(htmlURL, forKey: .htmlURL)
        try container.encodeIfPresent(publishedAt, forKey: .publishedAt)
        try container.encode(prerelease, forKey: .prerelease)
        try container.encodeIfPresent(appAssetURL, forKey: .appAssetURL)
    }
}

enum UpdateCheckResponse: Sendable {
    case release(GitHubReleaseInfo, eTag: String?)
    case notModified
}

protocol GitHubReleaseFetching: Sendable {
    func fetchLatestRelease(eTag: String?) async throws -> UpdateCheckResponse
}

struct GitHubReleaseClient: GitHubReleaseFetching, Sendable {
    static let repository = "Shawn66168/AI-Usage-Monitor"
    static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/\(repository)/releases/latest"
    )!

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    func makeRequest(eTag: String?) -> URLRequest {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("AI-Usage-Monitor", forHTTPHeaderField: "User-Agent")
        if let eTag, !eTag.isEmpty {
            request.setValue(eTag, forHTTPHeaderField: "If-None-Match")
        }
        return request
    }

    func fetchLatestRelease(eTag: String?) async throws -> UpdateCheckResponse {
        let request = makeRequest(eTag: eTag)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AppUpdateError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AppUpdateError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            guard data.count <= 1_048_576 else {
                throw AppUpdateError.responseTooLarge
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let release: GitHubReleaseInfo
            do {
                release = try decoder.decode(GitHubReleaseInfo.self, from: data)
            } catch {
                throw AppUpdateError.invalidPayload(error.localizedDescription)
            }
            guard release.semanticVersion != nil else {
                throw AppUpdateError.invalidVersion(release.tagName)
            }
            guard Self.isTrustedReleaseURL(release.htmlURL) else {
                throw AppUpdateError.untrustedURL
            }
            return .release(release, eTag: http.value(forHTTPHeaderField: "ETag"))
        case 304:
            return .notModified
        case 403, 429:
            throw AppUpdateError.rateLimited
        case 404:
            throw AppUpdateError.releaseNotFound
        default:
            throw AppUpdateError.httpStatus(http.statusCode)
        }
    }

    static func isTrustedReleaseURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "github.com" else {
            return false
        }
        return url.path.hasPrefix("/Shawn66168/AI-Usage-Monitor/releases/")
    }
}

enum AppUpdateError: LocalizedError, Sendable {
    case network(String)
    case invalidResponse
    case invalidPayload(String)
    case invalidVersion(String)
    case responseTooLarge
    case untrustedURL
    case rateLimited
    case releaseNotFound
    case httpStatus(Int)
    case openURLFailed

    var errorDescription: String? {
        switch self {
        case let .network(message):
            "網路連線失敗：\(message)"
        case .invalidResponse:
            "GitHub 回應格式不正確"
        case let .invalidPayload(message):
            "無法解析 GitHub Release：\(message)"
        case let .invalidVersion(tag):
            "GitHub Release Tag 不是有效版本：\(tag)"
        case .responseTooLarge:
            "GitHub Release 回應超過安全大小限制"
        case .untrustedURL:
            "GitHub Release 連結未通過安全白名單"
        case .rateLimited:
            "GitHub 暫時限制請求，稍後會再檢查"
        case .releaseNotFound:
            "找不到公開的正式 GitHub Release"
        case .openURLFailed:
            "無法開啟 GitHub Release 頁面"
        case let .httpStatus(code):
            "GitHub Update API 回傳 HTTP \(code)"
        }
    }
}

struct UpdatePreferences: Codable, Equatable, Sendable {
    var automaticChecksEnabled = true
    var checkIntervalHours: Double = 6
    var ignoredVersion: String?
}

enum AppUpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case updateAvailable
    case failed(String)
}

@MainActor
final class AppUpdateStore: ObservableObject {
    @Published private(set) var state: AppUpdateState = .idle
    @Published private(set) var latestRelease: GitHubReleaseInfo?
    @Published private(set) var lastChecked: Date?
    @Published var preferences: UpdatePreferences {
        didSet {
            preferencesStore.save(preferences)
            evaluateState()
            restartAutomaticChecksIfNeeded()
        }
    }

    let currentVersion: SemanticVersion
    let currentVersionString: String

    private let client: any GitHubReleaseFetching
    private let cacheStore: UpdateCacheStore
    private let preferencesStore: UpdatePreferencesStore
    private var eTag: String?
    private var automaticCheckTask: Task<Void, Never>?
    private var automaticChecksStarted = false

    init(
        currentVersionString: String? = nil,
        client: any GitHubReleaseFetching = GitHubReleaseClient(),
        cacheStore: UpdateCacheStore = UpdateCacheStore(),
        preferencesStore: UpdatePreferencesStore = UpdatePreferencesStore()
    ) {
        let bundleVersion = currentVersionString
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.0"
        self.currentVersionString = bundleVersion
        self.currentVersion = SemanticVersion(bundleVersion) ?? SemanticVersion("0.0.0")!
        self.client = client
        self.cacheStore = cacheStore
        self.preferencesStore = preferencesStore
        self.preferences = preferencesStore.load()

        let cache = cacheStore.load()
        self.latestRelease = cache?.release
        self.lastChecked = cache?.lastChecked
        self.eTag = cache?.eTag
        evaluateState()
    }

    var availableRelease: GitHubReleaseInfo? {
        guard let latestRelease,
              !latestRelease.prerelease,
              let remoteVersion = latestRelease.semanticVersion,
              remoteVersion > currentVersion,
              preferences.ignoredVersion != latestRelease.versionDescription else {
            return nil
        }
        return latestRelease
    }

    var hasAvailableUpdate: Bool {
        availableRelease != nil
    }

    var statusDescription: String {
        switch state {
        case .idle:
            "尚未檢查更新"
        case .checking:
            "正在檢查 GitHub Releases"
        case .upToDate:
            "目前已是最新版本"
        case .updateAvailable:
            "有新版本可用"
        case let .failed(message):
            message
        }
    }

    func start() {
        guard !automaticChecksStarted else { return }
        automaticChecksStarted = true
        startAutomaticCheckLoop()
    }

    func stop() {
        automaticChecksStarted = false
        automaticCheckTask?.cancel()
        automaticCheckTask = nil
    }

    func checkNow(ignoreETag: Bool = false) async {
        guard state != .checking else { return }
        state = .checking

        do {
            let response = try await client.fetchLatestRelease(
                eTag: ignoreETag ? nil : eTag
            )
            let checkedAt = Date()
            lastChecked = checkedAt

            switch response {
            case let .release(release, newETag):
                latestRelease = release
                eTag = newETag
                cacheStore.save(
                    UpdateCache(
                        release: release,
                        eTag: newETag,
                        lastChecked: checkedAt
                    )
                )
            case .notModified:
                guard let latestRelease else {
                    throw AppUpdateError.invalidResponse
                }
                cacheStore.save(
                    UpdateCache(
                        release: latestRelease,
                        eTag: eTag,
                        lastChecked: checkedAt
                    )
                )
            }
            evaluateState()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func ignoreLatestVersion() {
        guard let latestRelease else { return }
        var updated = preferences
        updated.ignoredVersion = latestRelease.versionDescription
        preferences = updated
    }

    func clearIgnoredVersion() {
        var updated = preferences
        updated.ignoredVersion = nil
        preferences = updated
    }

    private func evaluateState() {
        if hasAvailableUpdate {
            state = .updateAvailable
        } else if latestRelease != nil {
            state = .upToDate
        } else if state != .checking {
            state = .idle
        }
    }

    private func restartAutomaticChecksIfNeeded() {
        guard automaticChecksStarted else { return }
        automaticCheckTask?.cancel()
        startAutomaticCheckLoop()
    }

    private func startAutomaticCheckLoop() {
        automaticCheckTask = Task { [weak self] in
            guard let self else { return }

            if self.preferences.automaticChecksEnabled,
               self.shouldCheckAutomatically {
                await self.checkNow()
            }

            while !Task.isCancelled {
                guard self.preferences.automaticChecksEnabled else { return }
                let seconds = max(3_600, self.preferences.checkIntervalHours * 3_600)
                do {
                    try await Task.sleep(for: .seconds(seconds))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self.checkNow()
            }
        }
    }

    private var shouldCheckAutomatically: Bool {
        guard let lastChecked else { return true }
        let interval = max(3_600, preferences.checkIntervalHours * 3_600)
        return Date().timeIntervalSince(lastChecked) >= interval
    }
}

struct UpdateCache: Codable, Sendable {
    let release: GitHubReleaseInfo
    let eTag: String?
    let lastChecked: Date
}

struct UpdateCacheStore: Sendable {
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
        self.fileURL = directory.appendingPathComponent("update-cache.json")
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() -> UpdateCache? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UpdateCache.self, from: data)
    }

    func save(_ cache: UpdateCache) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(cache) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}

struct UpdatePreferencesStore {
    private let key: String
    private let defaults: UserDefaults

    init(
        key: String = "AIUsageMonitor.updatePreferences.v1",
        defaults: UserDefaults = .standard
    ) {
        self.key = key
        self.defaults = defaults
    }

    func load() -> UpdatePreferences {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(UpdatePreferences.self, from: data) else {
            return UpdatePreferences()
        }
        return value
    }

    func save(_ preferences: UpdatePreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }
}
