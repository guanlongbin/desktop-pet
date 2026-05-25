import Foundation

/// 喂给大模型的事实 + 兜底本地文案
struct CountdownFact {
    let factLine: String
    let fallbackLine: String
}

/// 周末 / 假期倒计时。
/// 节假日表写到 2027 年(2026 年的够你用到明年了);过期了再加。
enum Countdown {
    /// 主要法定假期(开始日期, 名字)。
    private static let holidays: [(date: String, name: String)] = [
        // 2026
        ("2026-05-01", "五一"),
        ("2026-06-19", "端午"),
        ("2026-09-25", "中秋"),
        ("2026-10-01", "国庆"),
        ("2027-01-01", "元旦"),
        ("2027-02-16", "春节"),
        // 2027
        ("2027-04-05", "清明"),
        ("2027-05-01", "五一"),
        ("2027-06-09", "端午"),
        ("2027-09-15", "中秋"),
        ("2027-10-01", "国庆")
    ]

    /// 返回今天该不该弹周末/假期消息,弹什么。
    /// 只在 17:00 之后才会出周五消息。早于 17:00 / 不到提示日 → nil。
    static func todayTip(now: Date = Date()) -> String? {
        return todayFact(now: now)?.fallbackLine
    }

    /// 喂给大模型用的事实结构。如果今天不该提醒,返回 nil。
    static func todayFact(now: Date = Date()) -> CountdownFact? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let comps = cal.dateComponents([.weekday, .hour], from: now)
        guard let weekday = comps.weekday, let hour = comps.hour else { return nil }

        if let (days, name) = nextHoliday(from: now, calendar: cal), days >= 1, days <= 7 {
            if days == 1 {
                return CountdownFact(
                    factLine: "明天就是\(name)假期",
                    fallbackLine: "明天就是\(name)，今晚可以放松点"
                )
            } else {
                return CountdownFact(
                    factLine: "再 \(days) 天就是\(name)假期",
                    fallbackLine: "再 \(days) 天就到\(name)了，再撑一下"
                )
            }
        }

        if weekday == 6 && hour >= 17 {
            return CountdownFact(
                factLine: "今天是周五傍晚，明天周末",
                fallbackLine: "周五晚上了，再撑几小时就周末，辛苦了"
            )
        }

        return nil
    }

    private static func nextHoliday(from now: Date, calendar: Calendar) -> (daysAway: Int, name: String)? {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.timeZone = calendar.timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        let today = calendar.startOfDay(for: now)
        var best: (Int, String)?
        for (dateStr, name) in holidays {
            guard let d = fmt.date(from: dateStr) else { continue }
            let start = calendar.startOfDay(for: d)
            guard let diff = calendar.dateComponents([.day], from: today, to: start).day else { continue }
            if diff < 0 { continue }
            if best == nil || diff < best!.0 {
                best = (diff, name)
            }
        }
        return best
    }
}
