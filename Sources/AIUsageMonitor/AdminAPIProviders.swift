import Foundation

struct AnthropicAdminProvider: UsageProvider {
    let kind: ServiceKind = .anthropicAPI
    private let keychain: KeychainStore

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    func fetchSnapshot() async -> AIServiceSnapshot {
        do {
            guard let key = try keychain.read(.anthropicAdminKey), !key.isEmpty else {
                return .placeholder(
                    for: kind,
                    status: .needsConfiguration("請在設定中加入 sk-ant-admin 開頭的組織管理金鑰"),
                    source: "Anthropic Usage & Cost Admin API"
                )
            }

            async let usage = fetchUsage(key: key)
            async let cost = fetchCost(key: key)
            let (tokenUsage, costUsage) = try await (usage, cost)

            return AIServiceSnapshot(
                id: kind,
                planName: "API 組織",
                tokenUsage: tokenUsage,
                costUsage: costUsage,
                status: .available,
                sourceDescription: "Anthropic Usage & Cost Admin API",
                fetchedAt: Date()
            )
        } catch {
            return .placeholder(
                for: kind,
                status: apiStatus(for: error, service: "Anthropic"),
                source: "Anthropic Usage & Cost Admin API"
            )
        }
    }

    private func fetchUsage(key: String) async throws -> TokenUsage {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        var components = URLComponents(
            string: "https://api.anthropic.com/v1/organizations/usage_report/messages"
        )!
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: rfc3339(start)),
            URLQueryItem(name: "ending_at", value: rfc3339(now)),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "31")
        ]

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await APIClient.data(for: request)
        let payload = try JSONDecoder().decode(AnthropicUsageResponse.self, from: data)
        let results = payload.data.flatMap(\.results)

        let input = results.reduce(Int64(0)) { $0 + $1.uncachedInputTokens }
        let cached = results.reduce(Int64(0)) { $0 + $1.cacheReadInputTokens }
        let cacheWrite = results.reduce(Int64(0)) {
            $0 + $1.cacheCreation5mInputTokens + $1.cacheCreation1hInputTokens
        }
        let output = results.reduce(Int64(0)) { $0 + $1.outputTokens }

        return TokenUsage(
            inputTokens: input,
            cachedInputTokens: cached,
            cacheWriteInputTokens: cacheWrite,
            outputTokens: output,
            totalTokens: input + cached + cacheWrite + output,
            periodLabel: "近 7 天（Anthropic API 組織）"
        )
    }

    private func fetchCost(key: String) async throws -> CostUsage {
        let now = Date()
        let start = Calendar.current.dateInterval(of: .month, for: now)?.start ?? now
        var components = URLComponents(
            string: "https://api.anthropic.com/v1/organizations/cost_report"
        )!
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: rfc3339(start)),
            URLQueryItem(name: "ending_at", value: rfc3339(now)),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "31")
        ]

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await APIClient.data(for: request)
        let payload = try JSONDecoder().decode(AnthropicCostResponse.self, from: data)
        let lowestCurrencyUnitTotal = payload.data
            .flatMap(\.results)
            .filter { $0.currency.uppercased() == "USD" }
            .reduce(Decimal.zero) { partial, item in
                partial + (Decimal(string: item.amount) ?? .zero)
            }
        let amountUSD = NSDecimalNumber(decimal: lowestCurrencyUnitTotal / 100).doubleValue
        return CostUsage(amountUSD: amountUSD, periodLabel: "本月 Anthropic API 組織")
    }
}

struct OpenAIAdminProvider: UsageProvider {
    let kind: ServiceKind = .openAIAPI
    private let keychain: KeychainStore

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    func fetchSnapshot() async -> AIServiceSnapshot {
        do {
            guard let key = try keychain.read(.openAIAdminKey), !key.isEmpty else {
                return .placeholder(
                    for: kind,
                    status: .needsConfiguration("請在設定中加入 OpenAI Organization Admin Key"),
                    source: "OpenAI Organization Usage API"
                )
            }

            async let usage = fetchUsage(key: key)
            async let cost = fetchCost(key: key)
            let (tokenUsage, costUsage) = try await (usage, cost)

            return AIServiceSnapshot(
                id: kind,
                planName: "API 組織",
                tokenUsage: tokenUsage,
                costUsage: costUsage,
                status: .available,
                sourceDescription: "OpenAI Organization Usage & Costs API",
                fetchedAt: Date()
            )
        } catch {
            return .placeholder(
                for: kind,
                status: apiStatus(for: error, service: "OpenAI"),
                source: "OpenAI Organization Usage API"
            )
        }
    }

    private func fetchUsage(key: String) async throws -> TokenUsage {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        var components = URLComponents(
            string: "https://api.openai.com/v1/organization/usage/completions"
        )!
        components.queryItems = [
            URLQueryItem(name: "start_time", value: "\(Int(start.timeIntervalSince1970))"),
            URLQueryItem(name: "end_time", value: "\(Int(now.timeIntervalSince1970))"),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "7")
        ]

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await APIClient.data(for: request)
        let payload = try JSONDecoder().decode(OpenAIUsageResponse.self, from: data)
        let results = payload.data.flatMap(\.results)

        let input = results.reduce(Int64(0)) { $0 + $1.inputTokens }
        let cached = results.reduce(Int64(0)) { $0 + $1.inputCachedTokens }
        let cacheWrite = results.reduce(Int64(0)) { $0 + $1.inputCacheWriteTokens }
        let output = results.reduce(Int64(0)) { $0 + $1.outputTokens }

        return TokenUsage(
            inputTokens: input,
            cachedInputTokens: cached,
            cacheWriteInputTokens: cacheWrite,
            outputTokens: output,
            totalTokens: input + output,
            periodLabel: "近 7 天（OpenAI API 組織）"
        )
    }

    private func fetchCost(key: String) async throws -> CostUsage {
        let now = Date()
        let start = Calendar.current.dateInterval(of: .month, for: now)?.start ?? now
        var components = URLComponents(
            string: "https://api.openai.com/v1/organization/costs"
        )!
        components.queryItems = [
            URLQueryItem(name: "start_time", value: "\(Int(start.timeIntervalSince1970))"),
            URLQueryItem(name: "end_time", value: "\(Int(now.timeIntervalSince1970))"),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "31")
        ]

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await APIClient.data(for: request)
        let payload = try JSONDecoder().decode(OpenAICostResponse.self, from: data)
        let amountUSD = payload.data
            .flatMap(\.results)
            .filter { $0.amount.currency.lowercased() == "usd" }
            .reduce(0.0) { $0 + $1.amount.value }
        return CostUsage(amountUSD: amountUSD, periodLabel: "本月 OpenAI API 組織")
    }
}

private enum APIClient {
    static func data(for request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ProviderError.network("缺少 HTTP 回應")
            }
            guard 200 ..< 300 ~= http.statusCode else {
                let message = parseErrorMessage(data) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                throw ProviderError.httpStatus(http.statusCode, message)
            }
            return data
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.network(error.localizedDescription)
        }
    }

    private static func parseErrorMessage(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return object["message"] as? String
    }
}

private func apiStatus(for error: Error, service: String) -> ProviderStatus {
    if case let ProviderError.httpStatus(code, _) = error, code == 401 || code == 403 {
        return .needsConfiguration("\(service) 管理金鑰無效或權限不足")
    }
    return .error(error.localizedDescription)
}

private func rfc3339(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}

private struct AnthropicUsageResponse: Decodable {
    let data: [AnthropicUsageBucket]
}

private struct AnthropicUsageBucket: Decodable {
    let results: [AnthropicUsageResult]
}

private struct AnthropicUsageResult: Decodable {
    let uncachedInputTokens: Int64
    let cacheReadInputTokens: Int64
    let cacheCreation5mInputTokens: Int64
    let cacheCreation1hInputTokens: Int64
    let outputTokens: Int64

    enum CodingKeys: String, CodingKey {
        case uncachedInputTokens = "uncached_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreation5mInputTokens = "cache_creation_5m_input_tokens"
        case cacheCreation1hInputTokens = "cache_creation_1h_input_tokens"
        case outputTokens = "output_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uncachedInputTokens = try container.decodeIfPresent(Int64.self, forKey: .uncachedInputTokens) ?? 0
        cacheReadInputTokens = try container.decodeIfPresent(Int64.self, forKey: .cacheReadInputTokens) ?? 0
        cacheCreation5mInputTokens = try container.decodeIfPresent(Int64.self, forKey: .cacheCreation5mInputTokens) ?? 0
        cacheCreation1hInputTokens = try container.decodeIfPresent(Int64.self, forKey: .cacheCreation1hInputTokens) ?? 0
        outputTokens = try container.decodeIfPresent(Int64.self, forKey: .outputTokens) ?? 0
    }
}

private struct AnthropicCostResponse: Decodable {
    let data: [AnthropicCostBucket]
}

private struct AnthropicCostBucket: Decodable {
    let results: [AnthropicCostResult]
}

private struct AnthropicCostResult: Decodable {
    let currency: String
    let amount: String
}

private struct OpenAIUsageResponse: Decodable {
    let data: [OpenAIUsageBucket]
}

private struct OpenAIUsageBucket: Decodable {
    let results: [OpenAIUsageResult]
}

private struct OpenAIUsageResult: Decodable {
    let inputTokens: Int64
    let inputCachedTokens: Int64
    let inputCacheWriteTokens: Int64
    let outputTokens: Int64

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case inputCachedTokens = "input_cached_tokens"
        case inputCacheWriteTokens = "input_cache_write_tokens"
        case outputTokens = "output_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try container.decodeIfPresent(Int64.self, forKey: .inputTokens) ?? 0
        inputCachedTokens = try container.decodeIfPresent(Int64.self, forKey: .inputCachedTokens) ?? 0
        inputCacheWriteTokens = try container.decodeIfPresent(Int64.self, forKey: .inputCacheWriteTokens) ?? 0
        outputTokens = try container.decodeIfPresent(Int64.self, forKey: .outputTokens) ?? 0
    }
}

private struct OpenAICostResponse: Decodable {
    let data: [OpenAICostBucket]
}

private struct OpenAICostBucket: Decodable {
    let results: [OpenAICostResult]
}

private struct OpenAICostResult: Decodable {
    let amount: OpenAICostAmount
}

private struct OpenAICostAmount: Decodable {
    let value: Double
    let currency: String
}
