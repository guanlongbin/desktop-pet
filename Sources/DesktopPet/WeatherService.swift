import Foundation

/// 从 wttr.in 拉天气。format=j1 返回三天的 JSON,我们只挑明天那一天。
actor WeatherService {
    /// 海淀区。wttr.in 中文支持差,直接给英文/拼音最稳。
    static let defaultCity = "Haidian"

    private let session: URLSession
    private let city: String

    init(city: String = WeatherService.defaultCity) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 12
        self.session = URLSession(configuration: config)
        self.city = city
    }

    /// 给大模型用:明天的天气结构化摘要。失败返回 nil。
    func tomorrowSummary() async -> WeatherSummary? {
        guard let raw = try? await fetch() else { return nil }
        guard let day = raw.weather.dropFirst().first else { return nil }
        let maxT = Int(day.maxtempC) ?? 0
        let minT = Int(day.mintempC) ?? 0
        let hourly = day.hourly
        let willRain = hourly.contains { (Double($0.precipMM) ?? 0) >= 0.5 }
        let willSnow = hourly.contains { ($0.weatherDesc.first?.value ?? "").lowercased().contains("snow") }
        let maxWind = hourly.compactMap { Int($0.windspeedKmph) }.max() ?? 0
        let descSet = Set(hourly.compactMap { $0.weatherDesc.first?.value.lowercased() })
        let desc = descSet.sorted().joined(separator: ", ")
        return WeatherSummary(
            city: city,
            minTempC: minT,
            maxTempC: maxT,
            willRain: willRain,
            willSnow: willSnow,
            maxWindKmph: maxWind,
            descriptionsLowercased: desc
        )
    }

    /// 兜底本地静态文案,用于 DeepSeek 失败时显示。
    func tomorrowFallback() async -> String? {
        guard let s = await tomorrowSummary() else { return nil }
        if s.willSnow {
            return "明天有雪，\(s.minTempC) 到 \(s.maxTempC) 度，路上慢一点"
        } else if s.willRain {
            return "明天有雨，\(s.minTempC) 到 \(s.maxTempC) 度，包里塞把伞吧"
        } else if s.maxTempC <= 5 {
            return "明天 \(s.minTempC) 到 \(s.maxTempC) 度，特别冷，记得多穿"
        } else if s.maxTempC >= 30 {
            return "明天最高 \(s.maxTempC) 度，会很热，多喝水"
        }
        return "明天 \(s.minTempC) 到 \(s.maxTempC) 度，看起来还行，好好睡"
    }

    private func fetch() async throws -> WttrResponse {
        let urlStr = "https://wttr.in/\(city)?format=j1&lang=zh"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.setValue("curl/8", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: req)
        return try JSONDecoder().decode(WttrResponse.self, from: data)
    }
}

struct WeatherSummary: Sendable {
    let city: String
    let minTempC: Int
    let maxTempC: Int
    let willRain: Bool
    let willSnow: Bool
    let maxWindKmph: Int
    let descriptionsLowercased: String

    /// 喂给 DeepSeek 的纯事实描述(让模型只负责"翻译成温柔语气")。
    var promptDescription: String {
        var parts: [String] = []
        parts.append("城市:北京海淀")
        parts.append("明天最低 \(minTempC)°C,最高 \(maxTempC)°C")
        if willSnow { parts.append("明天有雪") }
        else if willRain { parts.append("明天有雨") }
        if maxWindKmph >= 30 { parts.append("最大风速约 \(maxWindKmph) km/h,风偏大") }
        if !descriptionsLowercased.isEmpty {
            parts.append("天气描述关键词:\(descriptionsLowercased)")
        }
        return parts.joined(separator: "；")
    }
}

// MARK: - wttr.in JSON

private struct WttrResponse: Decodable {
    let weather: [WttrDay]
}

private struct WttrDay: Decodable {
    let maxtempC: String
    let mintempC: String
    let hourly: [WttrHour]
}

private struct WttrHour: Decodable {
    let precipMM: String
    let windspeedKmph: String
    let weatherDesc: [WttrDesc]
}

private struct WttrDesc: Decodable {
    let value: String
}
