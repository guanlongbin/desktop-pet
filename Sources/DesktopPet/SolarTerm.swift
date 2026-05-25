import Foundation

/// 二十四节气。用经典的"通用计算公式"近似(21 世纪精度约 ±1 天,够桌面提醒用)。
/// 公式: [Y*D + C] - L,其中 Y 是年份后两位,D=0.2422,L 是闰年修正。
enum SolarTerm: Int, CaseIterable {
    case xiaohan, dahan
    case lichun, yushui
    case jingzhe, chunfen
    case qingming, guyu
    case lixia, xiaoman
    case mangzhong, xiazhi
    case xiaoshu, dashu
    case liqiu, chushu
    case bailu, qiufen
    case hanlu, shuangjiang
    case lidong, xiaoxue
    case daxue, dongzhi

    var displayName: String {
        switch self {
        case .xiaohan:    return "小寒"
        case .dahan:      return "大寒"
        case .lichun:     return "立春"
        case .yushui:     return "雨水"
        case .jingzhe:    return "惊蛰"
        case .chunfen:    return "春分"
        case .qingming:   return "清明"
        case .guyu:       return "谷雨"
        case .lixia:      return "立夏"
        case .xiaoman:    return "小满"
        case .mangzhong:  return "芒种"
        case .xiazhi:     return "夏至"
        case .xiaoshu:    return "小暑"
        case .dashu:      return "大暑"
        case .liqiu:      return "立秋"
        case .chushu:     return "处暑"
        case .bailu:      return "白露"
        case .qiufen:     return "秋分"
        case .hanlu:      return "寒露"
        case .shuangjiang:return "霜降"
        case .lidong:     return "立冬"
        case .xiaoxue:    return "小雪"
        case .daxue:      return "大雪"
        case .dongzhi:    return "冬至"
        }
    }

    /// 月份 + 21 世纪 C 值。
    private var formula: (month: Int, c: Double) {
        switch self {
        case .xiaohan:    return (1,  5.4055)
        case .dahan:      return (1, 20.12)
        case .lichun:     return (2,  4.475)
        case .yushui:     return (2, 19.112)
        case .jingzhe:    return (3,  6.103)
        case .chunfen:    return (3, 21.4429)
        case .qingming:   return (4,  5.59)
        case .guyu:       return (4, 20.888)
        case .lixia:      return (5,  6.318)
        case .xiaoman:    return (5, 21.86)
        case .mangzhong:  return (6,  6.5)
        case .xiazhi:     return (6, 22.20)
        case .xiaoshu:    return (7,  7.928)
        case .dashu:      return (7, 23.65)
        case .liqiu:      return (8,  8.35)
        case .chushu:     return (8, 23.95)
        case .bailu:      return (9,  8.44)
        case .qiufen:     return (9, 23.822)
        case .hanlu:      return (10, 9.098)
        case .shuangjiang:return (10,24.218)
        case .lidong:     return (11, 8.218)
        case .xiaoxue:    return (11,23.08)
        case .daxue:      return (12, 7.9)
        case .dongzhi:    return (12,22.60)
        }
    }

    /// 该节气在指定年的日期。
    func date(in year: Int) -> Date? {
        let (month, c) = formula
        let Y = year - 2000
        let D = 0.2422
        let L = (Y - 1) / 4  // 21 世纪闰年数
        let day = Int(Double(Y) * D + c) - L
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return Calendar(identifier: .gregorian).date(from: comps)
    }

    /// 提醒文案。挑一句温柔的。
    var tip: String {
        switch self {
        case .xiaohan, .dahan:
            return "今天\(displayName)，一年最冷的时候，多喝热水，别再赖被窝里玩手机"
        case .lichun:
            return "今天立春，春天来了，别急着收外套，乍暖还寒"
        case .yushui:
            return "今天雨水，多带把伞，不要又被淋到"
        case .jingzhe:
            return "今天惊蛰，春雷醒了，万物开始热闹"
        case .chunfen:
            return "今天春分，昼夜平分，最舒服的一天，到点睡哦"
        case .qingming:
            return "今天清明，记得想家"
        case .guyu:
            return "今天谷雨，春天的最后一个节气，要珍惜"
        case .lixia:
            return "今天立夏，开始要热了，记得擦防晒"
        case .xiaoman:
            return "今天小满，未盈即满，挺有意思的一天"
        case .mangzhong:
            return "今天芒种，最忙的时节，按时吃饭"
        case .xiazhi:
            return "今天夏至，一年里最长的白天，好好吃顿饭"
        case .xiaoshu, .dashu:
            return "今天\(displayName)，热得离谱，多喝水"
        case .liqiu:
            return "今天立秋，热归热，凉是真的快了"
        case .chushu:
            return "今天处暑，热气退场了"
        case .bailu:
            return "今天白露，早晚开始凉了，加件薄外套"
        case .qiufen:
            return "今天秋分，又一个昼夜平分，秋天才算正式来"
        case .hanlu:
            return "今天寒露，真凉了，秋裤备着"
        case .shuangjiang:
            return "今天霜降，秋天最后一个节气，外套上身吧"
        case .lidong:
            return "今天立冬，冬天到了，记得早点回家"
        case .xiaoxue, .daxue:
            return "今天\(displayName)，可能要下雪了，路上注意"
        case .dongzhi:
            return "今天冬至，吃饺子的日子，别又一个人凑合"
        }
    }

    /// 返回今天是不是某个节气;是的话返回它。
    static func today(in calendar: Calendar = .current) -> SolarTerm? {
        let now = Date()
        let comps = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = comps.year, let month = comps.month, let day = comps.day else { return nil }
        for term in SolarTerm.allCases {
            if term.formula.month != month { continue }
            guard let d = term.date(in: year) else { continue }
            let dc = calendar.dateComponents([.day], from: d)
            if dc.day == day { return term }
        }
        return nil
    }

    /// 喂给大模型当事实背景用的简短描述。
    var contextHint: String {
        switch self {
        case .xiaohan, .dahan: return "是一年中最冷的时段，北方常常下雪、刮干风"
        case .lichun:          return "象征春天开始，但其实还很冷，常常乍暖还寒"
        case .yushui:          return "雨开始多起来，气温回升"
        case .jingzhe:         return "春雷初响，万物开始活跃"
        case .chunfen:         return "昼夜平分，气温舒服"
        case .qingming:        return "传统扫墓节气，常下雨，天气转暖"
        case .guyu:            return "春天最后一个节气，雨水滋润作物"
        case .lixia:           return "夏天开始，气温明显上升"
        case .xiaoman:         return "麦类灌浆，未完全成熟，象征'未盈即满'"
        case .mangzhong:       return "农忙节气，气温高湿度大"
        case .xiazhi:          return "一年中白天最长的一天，正式入夏盛"
        case .xiaoshu, .dashu: return "全年最热的时段，常常高温多雨"
        case .liqiu:           return "立秋后白天还热，但早晚开始凉"
        case .chushu:          return "暑气退场，开始变凉爽"
        case .bailu:           return "早晚露水变凉，秋意明显"
        case .qiufen:          return "昼夜再次平分，秋天正式来"
        case .hanlu:           return "气温明显变冷，开始要穿秋裤了"
        case .shuangjiang:     return "秋天最后一个节气，开始有霜，要加外套"
        case .lidong:          return "冬天开始，需要早点回家"
        case .xiaoxue, .daxue: return "开始下雪的时节，路上易滑"
        case .dongzhi:         return "一年中白天最短的一天，传统要吃饺子"
        }
    }
}
