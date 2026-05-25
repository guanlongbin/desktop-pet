import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var petWindow: PetWindow!
    private let behavior = BehaviorDriver()
    private let collapseTab = CollapseTab()

    private static let clickPool: [(PetAction, TimeInterval)] = [
        (.wave,   1.8),
        (.jump,   0.7),
        (.review, 2.0),
        (.wait,   2.4)
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[DesktopPet] launching...")
        petWindow = PetWindow()
        petWindow.onClick = { [weak self] in self?.handleClick() }
        petWindow.onRightClick = { [weak self] e in self?.handleRightClick(e) }
        petWindow.show()

        collapseTab.onClick = { [weak self] in self?.restore() }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            self.petWindow.setAction(.wave)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.petWindow.setAction(.idle)
            self.behavior.start(pet: self.petWindow)
        }
    }

    private func handleClick() {
        guard petWindow.currentAction == .idle else { return }
        let (action, dur) = Self.clickPool.randomElement()!
        behavior.suspend(for: dur + 1)
        petWindow.setAction(action)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(dur * 1_000_000_000))
            if petWindow.currentAction == action {
                petWindow.setAction(.idle)
            }
        }
    }

    private func handleRightClick(_ event: NSEvent) {
        let menu = NSMenu()

        let collapse = NSMenuItem(title: "收起", action: #selector(collapse), keyEquivalent: "")
        collapse.target = self
        menu.addItem(collapse)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        NSMenu.popUpContextMenu(menu, with: event, for: petWindow.view)
    }

    @objc private func collapse() {
        behavior.suspend(for: 86_400)
        petWindow.hide()
        collapseTab.show()
    }

    private func restore() {
        collapseTab.hide()
        petWindow.show()
        behavior.suspend(for: 0)
        petWindow.setAction(.wave)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if self.petWindow.currentAction == .wave {
                self.petWindow.setAction(.idle)
            }
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
