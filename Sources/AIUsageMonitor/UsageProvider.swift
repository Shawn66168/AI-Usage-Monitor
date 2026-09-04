import Foundation

enum ProviderRefreshInterval {
    static let everyCycle: TimeInterval = 0
    static let adminAPI: TimeInterval = 15 * 60
}

protocol UsageProvider: Sendable {
    var kind: ServiceKind { get }
    var minimumRefreshInterval: TimeInterval { get }
    func fetchSnapshot() async -> AIServiceSnapshot
}

extension UsageProvider {
    var minimumRefreshInterval: TimeInterval {
        ProviderRefreshInterval.everyCycle
    }
}

struct ProviderRefreshGate {
    private var lastAttemptAt: [ServiceKind: Date] = [:]

    mutating func seed(_ kind: ServiceKind, lastAttemptAt date: Date) {
        lastAttemptAt[kind] = date
    }

    mutating func shouldRefresh(
        _ kind: ServiceKind,
        minimumInterval: TimeInterval,
        at date: Date,
        force: Bool = false
    ) -> Bool {
        let normalizedInterval = max(0, minimumInterval)
        guard normalizedInterval > 0 else { return true }

        if force {
            lastAttemptAt[kind] = date
            return true
        }

        guard let previous = lastAttemptAt[kind] else {
            lastAttemptAt[kind] = date
            return true
        }

        guard date.timeIntervalSince(previous) >= normalizedInterval else {
            return false
        }

        lastAttemptAt[kind] = date
        return true
    }

    func nextAllowedAt(
        for kind: ServiceKind,
        minimumInterval: TimeInterval
    ) -> Date? {
        guard minimumInterval > 0, let previous = lastAttemptAt[kind] else {
            return nil
        }
        return previous.addingTimeInterval(minimumInterval)
    }
}

enum ProviderError: LocalizedError, Sendable {
    case fileNotFound(String)
    case invalidData(String)
    case executableNotFound(String)
    case processFailed(String)
    case timedOut(String)
    case notAuthenticated(String)
    case serverOffline(String)
    case permissionDenied(String)
    case network(String)
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case let .fileNotFound(path):
            "找不到資料檔：\(path)"
        case let .invalidData(message):
            "資料格式無法解析：\(message)"
        case let .executableNotFound(name):
            "找不到可執行檔：\(name)"
        case let .processFailed(message):
            "本機程序執行失敗：\(message)"
        case let .timedOut(operation):
            "操作逾時：\(operation)"
        case let .notAuthenticated(service):
            "\(service) 尚未登入"
        case let .serverOffline(service):
            "\(service) 尚未啟動"
        case let .permissionDenied(resource):
            "沒有權限讀取：\(resource)"
        case let .network(message):
            "網路錯誤：\(message)"
        case let .httpStatus(code, message):
            "伺服器回應 \(code)：\(message)"
        }
    }
}

struct UnsupportedProvider: UsageProvider {
    let kind: ServiceKind
    let reason: String
    let sourceDescription: String

    func fetchSnapshot() async -> AIServiceSnapshot {
        .placeholder(
            for: kind,
            status: .unsupported(reason),
            source: sourceDescription
        )
    }
}

struct ConfigurationRequiredProvider: UsageProvider {
    let kind: ServiceKind
    let reason: String
    let sourceDescription: String

    func fetchSnapshot() async -> AIServiceSnapshot {
        .placeholder(
            for: kind,
            status: .needsConfiguration(reason),
            source: sourceDescription
        )
    }
}
