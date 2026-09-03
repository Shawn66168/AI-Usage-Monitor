import Foundation

struct AntigravityProvider: UsageProvider {
    let kind: ServiceKind = .antigravity

    func fetchSnapshot() async -> AIServiceSnapshot {
        do {
            let server = try await discoverServer()
            let response = try await fetchUserStatus(server: server)
            let quotas = response.groupedQuotaWindows

            guard !quotas.isEmpty else {
                throw ProviderError.invalidData("Antigravity 回應中沒有可用 quota")
            }

            return AIServiceSnapshot(
                id: .antigravity,
                quotas: quotas,
                status: .available,
                sourceDescription: "Antigravity 本機 Language Server",
                fetchedAt: Date()
            )
        } catch let error as ProviderError {
            let status: ProviderStatus
            switch error {
            case .serverOffline:
                status = .unavailable("請先啟動 Antigravity；本機 Language Server 執行時才可刷新 quota")
            default:
                status = .error(error.localizedDescription)
            }

            return .placeholder(
                for: kind,
                status: status,
                source: "Antigravity 本機 Language Server"
            )
        } catch {
            return .placeholder(
                for: kind,
                status: .error(error.localizedDescription),
                source: "Antigravity 本機 Language Server"
            )
        }
    }

    private func discoverServer() async throws -> AntigravityServer {
        let processList = try await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-axww", "-o", "pid=,command="],
            timeout: 5
        )

        guard processList.exitCode == 0 else {
            throw ProviderError.processFailed("無法取得 Antigravity 行程清單")
        }

        guard let line = processList.standardOutput
            .split(separator: "\n")
            .map(String.init)
            .first(where: { command in
                command.contains("language_server_macos")
                    && command.contains("--csrf_token")
                    && !command.contains("AIUsageMonitor")
            }) else {
            throw ProviderError.serverOffline("Antigravity")
        }

        let pieces = line.split(whereSeparator: { $0.isWhitespace })
        guard let first = pieces.first, let pid = Int32(first) else {
            throw ProviderError.invalidData("無法辨識 Antigravity Language Server PID")
        }

        guard let csrfToken = extractCSRFToken(from: line), !csrfToken.isEmpty else {
            throw ProviderError.invalidData("Antigravity Language Server 未提供 CSRF token")
        }

        let portResult = try await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: ["-nP", "-a", "-p", "\(pid)", "-iTCP", "-sTCP:LISTEN"],
            timeout: 5
        )

        let ports = extractListeningPorts(from: portResult.standardOutput)
        guard !ports.isEmpty else {
            throw ProviderError.invalidData("找不到 Antigravity Language Server 的本機連接埠")
        }

        return AntigravityServer(ports: ports, csrfToken: csrfToken)
    }

    private func extractCSRFToken(from command: String) -> String? {
        let patterns = [
            #"--csrf_token\s+([^\s]+)"#,
            #"--csrf_token=([^\s]+)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(
                    in: command,
                    range: NSRange(command.startIndex..., in: command)
                  ),
                  let range = Range(match.range(at: 1), in: command) else {
                continue
            }
            return String(command[range])
        }
        return nil
    }

    private func extractListeningPorts(from output: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: #":(\d+)\s+\(LISTEN\)"#) else {
            return []
        }

        let matches = regex.matches(
            in: output,
            range: NSRange(output.startIndex..., in: output)
        )
        let ports = matches.compactMap { match -> Int? in
            guard let range = Range(match.range(at: 1), in: output) else { return nil }
            return Int(output[range])
        }
        return Array(Set(ports)).sorted()
    }

    private func fetchUserStatus(server: AntigravityServer) async throws -> AntigravityResponse {
        let payload = AntigravityRequest(
            metadata: AntigravityRequest.Metadata(
                ideName: "antigravity",
                extensionName: "antigravity",
                locale: "zh-TW"
            )
        )
        let body = try JSONEncoder().encode(payload)
        var lastError: Error?

        for port in server.ports {
            guard let url = URL(
                string: "http://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/GetUserStatus"
            ) else {
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = body
            request.timeoutInterval = 3
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
            request.setValue(server.csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    lastError = ProviderError.network("本機連接埠 \(port) 未回傳成功狀態")
                    continue
                }
                let decoded = try JSONDecoder().decode(AntigravityResponse.self, from: data)
                if !decoded.modelConfigs.isEmpty {
                    return decoded
                }
            } catch {
                lastError = error
            }
        }

        throw lastError ?? ProviderError.invalidData("所有 Antigravity 本機連接埠皆無有效回應")
    }
}

private struct AntigravityServer: Sendable {
    let ports: [Int]
    let csrfToken: String
}

private struct AntigravityRequest: Encodable {
    struct Metadata: Encodable {
        let ideName: String
        let extensionName: String
        let locale: String
    }

    let metadata: Metadata
}

private struct AntigravityResponse: Decodable, Sendable {
    let userStatus: UserStatus?

    struct UserStatus: Decodable, Sendable {
        let cascadeModelConfigData: CascadeModelConfigData?
    }

    struct CascadeModelConfigData: Decodable, Sendable {
        let clientModelConfigs: [ModelConfig]?
    }

    struct ModelConfig: Decodable, Sendable {
        let label: String?
        let displayName: String?
        let quotaInfo: QuotaInfo?
    }

    struct QuotaInfo: Decodable, Sendable {
        let remainingFraction: Double?
        let resetTime: String?
    }

    var modelConfigs: [ModelConfig] {
        userStatus?.cascadeModelConfigData?.clientModelConfigs ?? []
    }

    var groupedQuotaWindows: [QuotaWindow] {
        var groups: [AntigravityBucketKey: [String]] = [:]

        for config in modelConfigs {
            guard let fraction = config.quotaInfo?.remainingFraction, fraction >= 0 else {
                continue
            }
            let remaining = (fraction * 100).clamped(to: 0 ... 100)
            let resetDate = config.quotaInfo?.resetTime.flatMap(FlexibleDateParser.parse)
            let name = config.label ?? config.displayName ?? "未命名模型"
            let key = AntigravityBucketKey(
                roundedRemaining: Int(remaining.rounded()),
                resetTimestamp: resetDate.map { Int($0.timeIntervalSince1970) }
            )
            groups[key, default: []].append(name)
        }

        return groups
            .map { key, names in
                let sortedNames = Array(Set(names)).sorted()
                let label = sortedNames.count == 1
                    ? sortedNames[0]
                    : "共享模型額度"
                let detail = sortedNames.count == 1
                    ? nil
                    : "\(sortedNames.prefix(3).joined(separator: "、"))\(sortedNames.count > 3 ? " 等 \(sortedNames.count) 個" : "")"

                return QuotaWindow(
                    id: "antigravity-\(key.roundedRemaining)-\(key.resetTimestamp ?? 0)-\(sortedNames.joined(separator: "-").hashValue)",
                    label: label,
                    remainingPercent: Double(key.roundedRemaining),
                    resetsAt: key.resetTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                    scope: .model,
                    detail: detail
                )
            }
            .sorted { lhs, rhs in
                if lhs.remainingPercent == rhs.remainingPercent {
                    return lhs.label < rhs.label
                }
                return lhs.remainingPercent < rhs.remainingPercent
            }
    }
}

private struct AntigravityBucketKey: Hashable, Sendable {
    let roundedRemaining: Int
    let resetTimestamp: Int?
}
