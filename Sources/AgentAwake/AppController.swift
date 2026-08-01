import AppKit
import Foundation
import AgentAwakeCore
import OSLog

final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let defaults = UserDefaults.standard
    private let sleepAssertion = SleepAssertionController()
    private let agentDetector = AgentActivityDetector()
    private let powerHelper = PowerHelperClient()
    private let brightnessController = BuiltInDisplayBrightnessController()
    private let launchAtLogin = LaunchAtLoginController()
    private let sleepProtectionSound = NSSound(
        contentsOfFile: "/System/Library/Sounds/Purr.aiff",
        byReference: true
    )
    private let energySuccessSound = NSSound(
        contentsOfFile: "/System/Library/Sounds/Tink.aiff",
        byReference: true
    )
    private let chargingWarning = ChargingWarningController()
    private let logger = Logger(subsystem: "com.rodion.agentawake", category: "state")
    private let detectorQueue = DispatchQueue(label: "com.rodion.agentawake.detector", qos: .utility)

    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var lidSoundTimer: Timer?
    private var mode: SessionMode = .off
    private var agents = AgentActivitySnapshot(codexActiveCount: 0, claudeActiveCount: 0)
    private var system = SystemSnapshot.current()
    private var agentsWereBusy = false
    private var hasCompletedAgentScan = false
    private var scanInProgress = false
    private var menuIsOpen = false
    private var clamshellSleepDisabled = false
    private var helperInstallAttempted = false
    private var lastError: String?
    private var pendingThermalAlert = false
    private var lastLoggedPolicy: String?
    private var brightnessAction = DelayedLidAction(delay: 10)
    private var sleepProtectionNotification = SleepProtectionNotification(delay: 1)
    private var energySuccessNotification = EnergySuccessNotification()

    private var keepAwakeWithLidClosed: Bool {
        get { boolDefault(forKey: "keepAwakeWithLidClosed", fallback: true) }
        set { defaults.set(newValue, forKey: "keepAwakeWithLidClosed") }
    }

    private var thermalProtectionEnabled: Bool {
        get { boolDefault(forKey: "thermalProtectionEnabled", fallback: false) }
        set { defaults.set(newValue, forKey: "thermalProtectionEnabled") }
    }

    private var releaseAfterAgents: Bool {
        get { boolDefault(forKey: "releaseAfterAgents", fallback: true) }
        set { defaults.set(newValue, forKey: "releaseAfterAgents") }
    }

    private var sleepAfterAgents: Bool {
        get { boolDefault(forKey: "sleepAfterAgents", fallback: false) }
        set { defaults.set(newValue, forKey: "sleepAfterAgents") }
    }

    private var lastCustomMinutes: Int {
        get {
            let stored = defaults.integer(forKey: "lastCustomMinutes")
            return TimedSession.allowedMinutes.contains(stored) ? stored : 15
        }
        set { defaults.set(newValue, forKey: "lastCustomMinutes") }
    }

    private var dimDisplayOnLidClose: Bool {
        get { boolDefault(forKey: "dimDisplayOnLidClose", fallback: true) }
        set { defaults.set(newValue, forKey: "dimDisplayOnLidClose") }
    }

    private var lowPowerOnLidClose: Bool {
        get { boolDefault(forKey: "lowPowerOnLidClose", fallback: true) }
        set { defaults.set(newValue, forKey: "lowPowerOnLidClose") }
    }

    private var brightnessWasDimmed: Bool {
        get { defaults.bool(forKey: "brightnessWasDimmed") }
        set { defaults.set(newValue, forKey: "brightnessWasDimmed") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination(
            "Agent Awake должен постоянно отслеживать активных агентов"
        )
        ProcessInfo.processInfo.disableSuddenTermination()
        mode = restoredMode()
        brightnessAction = DelayedLidAction(delay: 10, initiallyApplied: brightnessWasDimmed)
        logger.notice("launched mode=\(self.modeLogValue, privacy: .public)")
        configureStatusItem()
        configureLaunchAtLogin()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        timer = Timer.scheduledTimer(
            timeInterval: 2,
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer!, forMode: .common)

        lidSoundTimer = Timer.scheduledTimer(
            timeInterval: 0.25,
            target: self,
            selector: #selector(reconcileSleepProtectionNotification),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(lidSoundTimer!, forMode: .common)

        tick()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        lidSoundTimer?.invalidate()
        restoreBrightnessIfNeeded()
        restoreNormalSleep()
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        rebuildMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
    }

    @objc private func tick() {
        system = .current()
        let charging = ChargingDiagnostics.presentation(for: system.chargingTelemetry)
        chargingWarning.update(problemDetected: charging.shouldWarn)
        reconcileBrightness()
        do {
            try powerHelper.setLowPowerOnLidClose(lowPowerOnLidClose)
            try powerHelper.refresh()
        } catch {
            lastError = error.localizedDescription
            logger.error("heartbeat refresh failed: \(error.localizedDescription, privacy: .public)")
        }
        reconcileEnergySuccessNotification()
        evaluatePolicy()
        scanAgentsIfNeeded()
        updateStatusIcon()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusIcon()
        rebuildMenu()
    }

    private func scanAgentsIfNeeded() {
        guard !scanInProgress else { return }
        scanInProgress = true

        detectorQueue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.agentDetector.snapshot()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.agents = snapshot
                self.hasCompletedAgentScan = true
                if snapshot.totalActiveCount > 0 {
                    self.agentsWereBusy = true
                }
                self.scanInProgress = false
                self.evaluatePolicy()
                self.updateStatusIcon()
                if !self.menuIsOpen {
                    self.rebuildMenu()
                }
            }
        }
    }

    private func evaluatePolicy() {
        if mode == .agents && !hasCompletedAgentScan {
            return
        }

        let decision = AwakePolicy.evaluate(
            PolicyInput(
                mode: mode,
                now: Date(),
                activeAgentCount: agents.totalActiveCount,
                agentsWereBusy: agentsWereBusy,
                lidClosed: system.lidClosed,
                thermalLevel: system.thermalLevel,
                keepAwakeWithLidClosed: keepAwakeWithLidClosed,
                thermalProtectionEnabled: thermalProtectionEnabled,
                releaseAfterAgents: releaseAfterAgents,
                sleepAfterAgents: sleepAfterAgents
            )
        )

        logPolicyIfChanged(decision)

        applyPowerState(
            holdAwake: decision.shouldHoldAwake,
            disableClamshellSleep: decision.shouldDisableClamshellSleep
        )

        if decision.stopReason == .agentsFinished {
            agentsWereBusy = false
            if decision.shouldSleepNow {
                scheduleSleep()
            }
            return
        }

        guard decision.shouldEndSession else { return }

        mode = .off
        persistMode()
        agentsWereBusy = false

        if decision.stopReason == .thermalSafety {
            pendingThermalAlert = true
            defaults.set(true, forKey: "pendingThermalAlert")
        }

        if decision.shouldSleepNow {
            scheduleSleep()
        }
    }

    private func scheduleSleep() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.putMacToSleep()
        }
    }

    private func logPolicyIfChanged(_ decision: PolicyDecision) {
        let value = "mode=\(modeLogValue) agents=\(agents.totalActiveCount) busy=\(agentsWereBusy) hold=\(decision.shouldHoldAwake) lidHold=\(decision.shouldDisableClamshellSleep) stop=\(decision.stopReason)"
        guard value != lastLoggedPolicy else { return }
        lastLoggedPolicy = value
        logger.notice("policy \(value, privacy: .public)")
    }

    private var modeLogValue: String {
        switch mode {
        case .off: return "off"
        case .agents: return "agents"
        case .indefinite: return "indefinite"
        case let .timed(until): return "timed-until-\(Int(until.timeIntervalSince1970))"
        }
    }

    private func applyPowerState(holdAwake: Bool, disableClamshellSleep: Bool) {
        if holdAwake {
            let assertionResult = sleepAssertion.setHeld(true)
            if assertionResult != kIOReturnSuccess {
                lastError = "Не удалось запретить обычный сон (\(assertionResult))"
            }

            if disableClamshellSleep && !clamshellSleepDisabled {
                do {
                    if powerHelper.needsInstallation && !helperInstallAttempted {
                        helperInstallAttempted = true
                        try powerHelper.install()
                    }
                    guard !powerHelper.needsInstallation else {
                        lastError = "Для закрытой крышки нужно разрешить установку системного помощника"
                        return
                    }
                    try powerHelper.setDesired(true)
                    clamshellSleepDisabled = true
                } catch {
                    lastError = error.localizedDescription
                }
            } else if !disableClamshellSleep && clamshellSleepDisabled {
                restoreClamshellSleep()
            }
            return
        }

        if clamshellSleepDisabled {
            restoreClamshellSleep()
        }

        let assertionResult = sleepAssertion.setHeld(false)
        if assertionResult != kIOReturnSuccess {
            lastError = "Не удалось вернуть обычный сон (\(assertionResult))"
        }
    }

    private func restoreNormalSleep() {
        if clamshellSleepDisabled {
            restoreClamshellSleep()
        }
        _ = sleepAssertion.setHeld(false)
    }

    private func restoreClamshellSleep() {
        do {
            try powerHelper.setDesired(false)
            clamshellSleepDisabled = false
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func putMacToSleep() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["sleepnow"]

        do {
            try process.run()
        } catch {
            let script = NSAppleScript(source: "tell application \"System Events\" to sleep")
            var errorInfo: NSDictionary?
            script?.executeAndReturnError(&errorInfo)
            if let errorInfo {
                lastError = "Не удалось усыпить Mac: \(errorInfo)"
            }
        }
    }

    @objc private func systemDidWake() {
        guard pendingThermalAlert || defaults.bool(forKey: "pendingThermalAlert") else {
            return
        }
        pendingThermalAlert = false
        defaults.set(false, forKey: "pendingThermalAlert")

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Agent Awake защитно усыпил Mac"
        alert.informativeText = "Крышка была закрыта, а тепловой статус macOS стал опасным. Удержание отключено, чтобы Mac остыл."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Понятно")
        alert.runModal()
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        button.toolTip = statusTitle()

        if case let .timed(until) = mode, until > Date() {
            button.image = NSImage(
                systemSymbolName: "bolt.circle.fill",
                accessibilityDescription: statusTitle()
            )
            button.imagePosition = .imageLeading
            button.title = TimedSession.remainingLabel(until: until)
            statusItem.length = NSStatusItem.variableLength
            return
        }

        let symbol: String
        if system.thermalLevel.isDangerous && system.lidClosed {
            symbol = "exclamationmark.triangle.fill"
        } else if sleepAssertion.isHeld {
            symbol = "bolt.circle.fill"
        } else {
            symbol = "moon.zzz"
        }
        button.title = ""
        button.imagePosition = .imageOnly
        button.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: statusTitle()
        )
        statusItem.length = NSStatusItem.squareLength
    }

    private func rebuildMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()

        addDisabledItem(statusTitle(), to: menu)
        addDisabledItem("Агенты: \(agents.displayText)", to: menu)
        addDisabledItem("Нагрев: \(system.thermalLevel.displayName)", to: menu)
        addDisabledItem("Крышка: \(system.lidClosed ? "закрыта" : "открыта") · питание: \(system.powerDescription)", to: menu)
        let charging = ChargingDiagnostics.presentation(for: system.chargingTelemetry)
        for line in charging.menuLines {
            addDisabledItem(line, to: menu)
        }

        if let lastError {
            addDisabledItem("⚠︎ \(lastError)", to: menu)
        }

        if amphetamineIsRunning {
            addDisabledItem("⚠︎ Amphetamine запущен и может конфликтовать", to: menu)
            addActionItem("Завершить сессию Amphetamine", action: #selector(stopAmphetamineSession), to: menu)
        }

        menu.addItem(.separator())
        addModeItem("На 30 минут", seconds: 30 * 60, to: menu)
        addModeItem("На 1 час", seconds: 60 * 60, to: menu)
        addModeItem("На 2 часа", seconds: 2 * 60 * 60, to: menu)
        addActionItem("Своё время…", action: #selector(startCustomTimed), to: menu)
        addActionItem("Бессрочно", action: #selector(startIndefinite), state: mode == .indefinite, to: menu)
        addActionItem("Пока работают агенты", action: #selector(startAgents), state: mode == .agents, to: menu)
        addActionItem("Остановить удержание", action: #selector(stopSession), enabled: mode != .off, to: menu)

        menu.addItem(.separator())
        addActionItem(
            "После агентов: разрешить сон по настройкам macOS",
            action: #selector(toggleReleaseAfterAgents),
            state: releaseAfterAgents,
            to: menu
        )
        addActionItem(
            "После агентов: усыпить Mac сразу",
            action: #selector(toggleSleepAfterAgents),
            state: sleepAfterAgents,
            to: menu
        )
        addActionItem(
            "Работать с закрытой крышкой",
            action: #selector(toggleClosedLidMode),
            state: keepAwakeWithLidClosed,
            to: menu
        )
        menu.addItem(.separator())
        addActionItem(
            "При закрытии: яркость 0% через 10 с",
            action: #selector(toggleDimDisplayOnLidClose),
            state: dimDisplayOnLidClose,
            to: menu
        )
        addActionItem(
            "При закрытии: Low Power Mode через 10 с",
            action: #selector(toggleLowPowerOnLidClose),
            state: lowPowerOnLidClose,
            to: menu
        )
        addActionItem(
            "Защита закрытой крышки от перегрева",
            action: #selector(toggleThermalProtection),
            state: thermalProtectionEnabled,
            to: menu
        )

        menu.addItem(.separator())
        addActionItem("Инструкция", action: #selector(openDocumentation), to: menu)
        addActionItem("Выйти из Agent Awake", action: #selector(quitApplication), to: menu)
    }

    private func statusTitle() -> String {
        switch mode {
        case .off:
            return "Обычный сон разрешён"
        case let .timed(until):
            let remaining = max(0, Int(until.timeIntervalSinceNow))
            return "Mac не уснёт ещё \(formatDuration(remaining))"
        case .indefinite:
            return "Mac не уснёт · бессрочно"
        case .agents:
            if sleepAssertion.isHeld {
                return "Mac не уснёт · активных агентов: \(agents.totalActiveCount)"
            }
            return "Наблюдение за агентами включено · сон разрешён"
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return "\(hours) ч \(minutes) мин" }
        return "\(max(1, minutes)) мин"
    }

    private func addModeItem(_ title: String, seconds: Int, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: #selector(startTimed(_:)), keyEquivalent: "")
        item.target = self
        item.tag = seconds
        if case let .timed(until) = mode {
            let remaining = Int(until.timeIntervalSinceNow)
            item.state = abs(remaining - seconds) < 5 ? .on : .off
        }
        menu.addItem(item)
    }

    private func addActionItem(
        _ title: String,
        action: Selector,
        state: Bool = false,
        enabled: Bool = true,
        to menu: NSMenu
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = state ? .on : .off
        item.isEnabled = enabled
        menu.addItem(item)
    }

    private func addDisabledItem(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    @objc private func startTimed(_ sender: NSMenuItem) {
        startTimed(seconds: sender.tag)
    }

    private func startTimed(seconds: Int) {
        mode = .timed(until: Date().addingTimeInterval(TimeInterval(seconds)))
        persistMode()
        agentsWereBusy = false
        lastError = nil
        evaluatePolicy()
        updateStatusIcon()
        rebuildMenu()
    }

    @objc private func startCustomTimed() {
        let field = NSTextField(string: String(lastCustomMinutes))
        field.placeholderString = "1–60"
        field.frame.size = NSSize(width: 180, height: 24)

        let alert = NSAlert()
        alert.messageText = "Сколько минут не давать Mac уснуть?"
        alert.informativeText = "Введите целое число от 1 до 60."
        alert.alertStyle = .informational
        alert.accessoryView = field
        alert.addButton(withTitle: "Запустить")
        alert.addButton(withTitle: "Отмена")

        NSApp.activate(ignoringOtherApps: true)
        while alert.runModal() == .alertFirstButtonReturn {
            guard let minutes = TimedSession.parseMinutes(field.stringValue) else {
                NSSound.beep()
                alert.informativeText = "Нужно целое число от 1 до 60 минут."
                continue
            }
            lastCustomMinutes = minutes
            startTimed(seconds: minutes * 60)
            return
        }
    }

    @objc private func startIndefinite() {
        mode = .indefinite
        persistMode()
        agentsWereBusy = false
        lastError = nil
        evaluatePolicy()
        rebuildMenu()
    }

    @objc private func startAgents() {
        mode = .agents
        persistMode()
        agentsWereBusy = agents.totalActiveCount > 0
        lastError = nil
        evaluatePolicy()
        rebuildMenu()
    }

    @objc private func stopSession() {
        mode = .off
        persistMode()
        agentsWereBusy = false
        applyPowerState(holdAwake: false, disableClamshellSleep: false)
        rebuildMenu()
    }

    @objc private func toggleReleaseAfterAgents() {
        releaseAfterAgents.toggle()
        if !releaseAfterAgents && sleepAfterAgents {
            sleepAfterAgents = false
        }
        evaluatePolicy()
        rebuildMenu()
    }

    @objc private func toggleSleepAfterAgents() {
        sleepAfterAgents.toggle()
        if sleepAfterAgents {
            releaseAfterAgents = true
        }
        evaluatePolicy()
        rebuildMenu()
    }

    @objc private func toggleClosedLidMode() {
        keepAwakeWithLidClosed.toggle()
        evaluatePolicy()
        rebuildMenu()
    }

    @objc private func toggleDimDisplayOnLidClose() {
        dimDisplayOnLidClose.toggle()
        reconcileBrightness()
        rebuildMenu()
    }

    @objc private func toggleLowPowerOnLidClose() {
        lowPowerOnLidClose.toggle()
        do {
            try powerHelper.setLowPowerOnLidClose(lowPowerOnLidClose)
        } catch {
            lastError = error.localizedDescription
        }
        rebuildMenu()
    }

    @objc private func toggleThermalProtection() {
        thermalProtectionEnabled.toggle()
        evaluatePolicy()
        rebuildMenu()
    }

    @objc private func stopAmphetamineSession() {
        let script = NSAppleScript(source: "tell application \"Amphetamine\" to end session")
        var errorInfo: NSDictionary?
        script?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            lastError = "Amphetamine не ответил: \(errorInfo)"
        } else {
            lastError = nil
        }
        rebuildMenu()
    }

    @objc private func openDocumentation() {
        if let url = Bundle.main.url(forResource: "README", withExtension: "md") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    private var amphetamineIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.if.Amphetamine").isEmpty
    }

    private func boolDefault(forKey key: String, fallback: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.bool(forKey: key)
    }

    private func reconcileBrightness(now: Date = Date()) {
        let shouldDim = system.lidClosed && dimDisplayOnLidClose
        switch brightnessAction.update(shouldApply: shouldDim, now: now) {
        case .none:
            return
        case .apply:
            do {
                try brightnessController.setBrightness(0)
                brightnessWasDimmed = true
                logger.notice("built-in display brightness set to 0 after lid delay")
            } catch {
                brightnessAction = DelayedLidAction(delay: 10)
                lastError = error.localizedDescription
            }
        case .restore:
            restoreBrightnessIfNeeded()
        }
    }

    private func restoreBrightnessIfNeeded() {
        guard brightnessWasDimmed else { return }
        do {
            try brightnessController.setBrightness(0.5)
            brightnessWasDimmed = false
            logger.notice("built-in display brightness restored to 50 percent")
        } catch {
            brightnessAction = DelayedLidAction(delay: 10, initiallyApplied: true)
            lastError = error.localizedDescription
        }
    }

    private func reconcileEnergySuccessNotification() {
        let currentBrightness = try? brightnessController.currentBrightness()
        let brightnessIsDimmed = brightnessWasDimmed
            && currentBrightness.map { $0 <= 0.01 } == true
        let lowPowerIsApplied = FileManager.default.fileExists(
            atPath: PowerHeartbeat.lowPowerAppliedMarkerURL.path
        ) && ProcessInfo.processInfo.isLowPowerModeEnabled

        guard energySuccessNotification.update(
            lidClosed: system.lidClosed,
            dimmingEnabled: dimDisplayOnLidClose,
            lowPowerEnabled: lowPowerOnLidClose,
            brightnessIsDimmed: brightnessIsDimmed,
            lowPowerIsApplied: lowPowerIsApplied
        ) else {
            return
        }

        guard let energySuccessSound else {
            NSSound.beep()
            logger.notice("energy success fallback sound requested after both confirmations")
            return
        }
        energySuccessSound.stop()
        energySuccessSound.currentTime = 0
        if energySuccessSound.play() {
            logger.notice("energy saving Tink played after brightness and low power confirmation")
        } else {
            NSSound.beep()
            logger.notice("energy success fallback sound requested after Tink playback failure")
        }
    }

    @objc private func reconcileSleepProtectionNotification() {
        let lidClosed = ClamshellController.lidIsClosed() ?? system.lidClosed
        let protectionActive = keepAwakeWithLidClosed
            && clamshellSleepDisabled
            && sleepAssertion.isHeld
            && ClamshellController.systemSleepIsDisabled() == true

        guard sleepProtectionNotification.update(
            lidClosed: lidClosed,
            protectionActive: protectionActive
        ) else {
            return
        }

        guard let sleepProtectionSound else {
            NSSound.beep()
            logger.notice("sleep protection fallback sound requested after closed lid confirmation")
            return
        }
        sleepProtectionSound.stop()
        sleepProtectionSound.currentTime = 0
        if sleepProtectionSound.play() {
            logger.notice("sleep protection Purr played after closed lid confirmation")
        } else {
            NSSound.beep()
            logger.notice("sleep protection fallback sound requested after Purr playback failure")
        }
    }

    private func configureLaunchAtLogin() {
        do {
            try launchAtLogin.ensureEnabled()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func restoredMode() -> SessionMode {
        guard let stored = defaults.string(forKey: "sessionMode") else {
            return .agents
        }
        switch stored {
        case "off":
            return .off
        case "indefinite":
            return .indefinite
        case "timed":
            let until = Date(timeIntervalSince1970: defaults.double(forKey: "sessionUntil"))
            return until > Date() ? .timed(until: until) : .off
        default:
            return .agents
        }
    }

    private func persistMode() {
        switch mode {
        case .off:
            defaults.set("off", forKey: "sessionMode")
        case .agents:
            defaults.set("agents", forKey: "sessionMode")
        case .indefinite:
            defaults.set("indefinite", forKey: "sessionMode")
        case let .timed(until):
            defaults.set("timed", forKey: "sessionMode")
            defaults.set(until.timeIntervalSince1970, forKey: "sessionUntil")
        }
    }
}
