import AppKit

/// 让宠物自己动起来：每隔几秒挑一个动作(走、跑、跳、挥手、等待…),
/// 演完后回到 idle。聊天事件优先级更高,会暂停自主行为。
@MainActor
final class BehaviorDriver {
    weak var pet: PetWindow?
    private var timer: Timer?
    private var pausedUntil: Date?

    func start(pet: PetWindow) {
        self.pet = pet
        scheduleNext(after: TimeInterval.random(in: 4...8))
    }

    /// 在指定时长内不要打扰他(聊天/流式回复时调用)。
    func suspend(for seconds: TimeInterval) {
        pausedUntil = Date().addingTimeInterval(seconds)
    }

    private func scheduleNext(after seconds: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.fire()
            }
        }
    }

    private func fire() {
        guard let pet = pet else { return }
        if let until = pausedUntil, Date() < until {
            scheduleNext(after: 2.0)
            return
        }
        // 当前不在 idle,说明被聊天事件占用了,改天再来
        guard pet.currentAction == .idle else {
            scheduleNext(after: 3.0)
            return
        }

        let (action, duration) = pickAction()
        pet.setAction(action)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            // 跑步类动作会被 PetView 在撞墙时主动翻转 (runLeft <-> runRight),
            // 所以不能用 currentAction == action 判断,否则跑步永远停不下来。
            if pet.currentAction != .idle {
                pet.setAction(.idle)
            }
            self.scheduleNext(after: TimeInterval.random(in: 6...14))
        }
    }

    /// 按权重抽一个自主行为。idle 之间的小动作要轻量、自然。
    private func pickAction() -> (PetAction, TimeInterval) {
        // (动作, 权重, 持续时间)
        let pool: [(PetAction, Int, TimeInterval)] = [
            (.wave,     26, 1.8),
            (.wait,     24, 2.4),
            (.jump,     14, 0.7),
            (.review,   12, 2.0),
            (.runRight,  5, 1.2),
            (.runLeft,   5, 1.2),
            (.sprint,    2, 0.8)
        ]
        let total = pool.reduce(0) { $0 + $1.1 }
        var pick = Int.random(in: 0..<total)
        for item in pool {
            if pick < item.1 { return (item.0, item.2) }
            pick -= item.1
        }
        return (.wave, 1.8)
    }
}
