import Foundation

/// DeepSeek 流式 SSE 客户端。
/// - 用 `chat/completions` 带 `stream: true`,按 token 增量回调。
/// - 失败抛错;上层应该兜底成本地静态文案,不打扰用户。
actor DeepSeekClient {
    /// 从 `~/.config/desktop-pet/key.txt` 读 API key。文件不存在或为空就当没配置。
    private static func loadKey() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let path = home.appendingPathComponent(".config/desktop-pet/key.txt")
        guard let raw = try? String(contentsOf: path, encoding: .utf8) else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    private let apiKey: String?
    private let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!
    private let session: URLSession

    init() {
        self.apiKey = Self.loadKey()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 60
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg)
    }

    /// 返回 SSE 解析后的纯文本增量流。
    /// system / user 都是普通 prompt 字符串。
    /// 没配置 API key 时直接 finish(throwing:),上层会走兜底文案。
    nonisolated func stream(system: String, user: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let bytes = try await self.openStream(system: system, user: user)
                    for try await line in bytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        guard trimmed.hasPrefix("data:") else { continue }
                        let payload = String(trimmed.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty { continue }
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8) else { continue }
                        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = obj["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String,
                              !content.isEmpty else { continue }
                        continuation.yield(content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func openStream(system: String, user: String) async throws -> URLSession.AsyncBytes {
        guard let apiKey = apiKey else {
            throw NSError(domain: "DeepSeek", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "没配置 API key,请把 key 写到 ~/.config/desktop-pet/key.txt"])
        }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "model": "deepseek-chat",
            "stream": true,
            "temperature": 0.85,
            "max_tokens": 220,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user",   "content": user]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await session.bytes(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "DeepSeek", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "no http response"])
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "DeepSeek", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        return bytes
    }
}
