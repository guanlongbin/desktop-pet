import AppKit

/// 中央调度:每分钟看一次该不该弹消息。
/// 用 UserDefaults 记每条消息今天弹过没有,避免重复打扰。
@MainActor
final class NotificationScheduler {
    weak var pet: PetWindow?
    weak var bubble: SpeechBubble?

    private var timer: Timer?
    private let weather = WeatherService()
    private let llm = DeepSeekClient()
    private var streamTask: Task<Void, Never>?

    /// 几点弹明天天气
    private let weatherHour = 20
    private let weatherMinute = 30

    private let dateKey = "scheduler.lastDateKey"
    private let weatherSentKey = "scheduler.weatherSent"
    private let termSentKey = "scheduler.termSent"
    private let countdownSentKey = "scheduler.countdownSent"

    func start(pet: PetWindow, bubble: SpeechBubble) {
        self.pet = pet
        self.bubble = bubble
        rollDateIfNeeded()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self.tick()
        }
    }

    /// 右键菜单 "看看明天天气"
    func forceWeatherNow() {
        streamWeather()
    }

    private func tick() {
        rollDateIfNeeded()
        let now = Date()
        let comps = Calendar.current.dateComponents([.hour, .minute], from: now)
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0

        // 1. 天气
        let weatherSent = UserDefaults.standard.bool(forKey: weatherSentKey)
        if !weatherSent {
            if hour > weatherHour || (hour == weatherHour && minute >= weatherMinute) {
                UserDefaults.standard.set(true, forKey: weatherSentKey)
                streamWeather()
                return
            }
        }

        // 2. 节气
        let termSent = UserDefaults.standard.bool(forKey: termSentKey)
        if !termSent, hour >= 9, let term = SolarTerm.today() {
            UserDefaults.standard.set(true, forKey: termSentKey)
            streamSolarTerm(term)
            return
        }

        // 3. 倒计时
        let cdSent = UserDefaults.standard.bool(forKey: countdownSentKey)
        if !cdSent, let fact = Countdown.todayFact(now: now) {
            UserDefaults.standard.set(true, forKey: countdownSentKey)
            streamCountdown(fact: fact)
            return
        }
    }

    // MARK: - 流式分支

    private func streamWeather() {
        guard let pet = pet, let bubble = bubble, pet.isVisible else { return }
        cancelStream()
        bubble.beginStream(
            anchorWindowFrame: pet.frame,
            streamingFallback: "拉天气拉得有点慢，等下再试"
        )
        pet.setAction(.review)
        streamTask = Task { @MainActor in
            let summary = await self.weather.tomorrowSummary()
            let fallback = await self.weather.tomorrowFallback() ?? "拉不到天气，可能是网络抽风"
            let userPrompt: String
            if let s = summary {
                userPrompt = """
                请基于下面的事实,给我说一句温柔体贴、像女朋友/老婆口吻的"明天天气提醒",最多两句话,每句不超过 30 个字,不要用 emoji,不要"亲爱的""宝贝"这种肉麻称呼,自然一点。

                硬性要求:必须在话里说出"\(s.minTempC) 到 \(s.maxTempC) 度"这个温度区间(可以用阿拉伯数字),不要省略温度。

                事实:\(s.promptDescription)
                """
            } else {
                userPrompt = "我现在拉不到明天的天气数据,请用一句温柔自然的话告诉我"
            }
            await self.runStream(
                system: Self.systemPrompt,
                user: userPrompt,
                fallback: fallback,
                returnAction: pet.currentAction
            )
        }
    }

    private func streamSolarTerm(_ term: SolarTerm) {
        guard let pet = pet, let bubble = bubble, pet.isVisible else { return }
        cancelStream()
        bubble.beginStream(
            anchorWindowFrame: pet.frame,
            streamingFallback: term.tip
        )
        pet.setAction(.wave)
        let user = """
        请基于下面的事实，给我说一句温柔体贴、像女朋友/老婆口吻的节气提醒，最多两句话，30 字以内一句，不要 emoji，不要"亲爱的"这种肉麻称呼。

        事实：今天是\(term.displayName)。这个节气一般\(term.contextHint)。
        """
        streamTask = Task { @MainActor in
            await self.runStream(
                system: Self.systemPrompt,
                user: user,
                fallback: term.tip,
                returnAction: pet.currentAction
            )
        }
    }

    private func streamCountdown(fact: CountdownFact) {
        guard let pet = pet, let bubble = bubble, pet.isVisible else { return }
        cancelStream()
        bubble.beginStream(
            anchorWindowFrame: pet.frame,
            streamingFallback: fact.fallbackLine
        )
        pet.setAction(.wave)
        let user = """
        请基于下面的事实，给我说一句温柔体贴、像女朋友/老婆口吻的安慰/期待话，最多两句话，30 字以内一句，不要 emoji。

        事实：\(fact.factLine)
        """
        streamTask = Task { @MainActor in
            await self.runStream(
                system: Self.systemPrompt,
                user: user,
                fallback: fact.fallbackLine,
                returnAction: pet.currentAction
            )
        }
    }

    /// 共通的流式跑步:开 SSE -> 一段段 append -> end / fail
    private func runStream(system: String, user: String, fallback: String, returnAction: PetAction) async {
        guard let bubble = self.bubble else { return }
        do {
            let stream = self.llm.stream(system: system, user: user)
            var got = false
            for try await chunk in stream {
                if Task.isCancelled { return }
                got = true
                bubble.append(chunk)
            }
            if got {
                bubble.endStream()
            } else {
                bubble.failStream(fallback: fallback)
            }
        } catch {
            bubble.failStream(fallback: fallback)
        }
        // 流结束后,过几秒让宠物回 idle
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if let pet = self.pet, pet.currentAction == returnAction {
            pet.setAction(.idle)
        }
    }

    private func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
    }

    /// 跨过午夜要清掉今天弹过的标记。
    private func rollDateIfNeeded() {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: Date())
        let last = UserDefaults.standard.string(forKey: dateKey)
        if last != today {
            UserDefaults.standard.set(today, forKey: dateKey)
            UserDefaults.standard.set(false, forKey: weatherSentKey)
            UserDefaults.standard.set(false, forKey: termSentKey)
            UserDefaults.standard.set(false, forKey: countdownSentKey)
        }
    }

    private static let systemPrompt = """
    你是一只懂事的桌面小宠物，正在跟一个上班比较晚的男生主人对话。说话风格：自然、温柔、体贴，像关系很好的女朋友/老婆，但不要肉麻不要矫情，不要"亲爱的""宝贝"，不要emoji，不要颜文字。中文，不超过两句话。
    """
}
