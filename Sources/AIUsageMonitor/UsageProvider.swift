import Foundation

protocol UsageProvider: Sendable {
    var kind: ServiceKind { get }
    func fetchSnapshot() async -> AIServiceSnapshot
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
