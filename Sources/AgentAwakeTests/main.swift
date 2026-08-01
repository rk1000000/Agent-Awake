import Darwin
import Foundation
import AgentAwakeCore

struct TestFailure: Error {
    let message: String
}

var passed = 0
var failed = 0

func test(_ name: String, _ body: () throws -> Void) {
    do {
        try body()
        passed += 1
        print("PASS: \(name)")
    } catch {
        failed += 1
        print("FAIL: \(name) — \(error)")
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure(message: message) }
}

let now = Date(timeIntervalSince1970: 1_000)

test("свежий heartbeat включает защиту крышки") {
    let heartbeat = PowerHeartbeat(
        pid: 123,
        uid: 501,
        wantsClosedLidAwake: true,
        updatedAt: now.addingTimeInterval(-2)
    )
    try expect(heartbeat.isFresh(at: now), "свежий heartbeat отклонён")
}

test("устаревший heartbeat снимает защиту крышки") {
    let heartbeat = PowerHeartbeat(
        pid: 123,
        uid: 501,
        wantsClosedLidAwake: true,
        updatedAt: now.addingTimeInterval(-11)
    )
    try expect(!heartbeat.isFresh(at: now), "устаревший heartbeat принят")
}

test("heartbeat без запроса закрытой крышки не включает защиту") {
    let heartbeat = PowerHeartbeat(
        pid: 123,
        uid: 501,
        wantsClosedLidAwake: false,
        updatedAt: now
    )
    try expect(!heartbeat.isFresh(at: now), "выключенный heartbeat принят")
}

test("приложение и root-helper используют общий каталог heartbeat") {
    let path = PowerHeartbeat.url(for: 501).path
    try expect(
        path == "/tmp/com.rodion.agentawake.501.power-heartbeat",
        "heartbeat записывается не в /tmp: \(path)"
    )
}

test("heartbeat передаёт root-helper настройку Low Power Mode") {
    let heartbeat = PowerHeartbeat(
        pid: 123,
        uid: 501,
        wantsClosedLidAwake: true,
        lowPowerOnLidClose: true,
        updatedAt: now
    )
    let data = try JSONEncoder().encode(heartbeat)
    let decoded = try JSONDecoder().decode(PowerHeartbeat.self, from: data)
    try expect(decoded.lowPowerOnLidClose, "настройка Low Power Mode потеряна")
}

test("root-helper отклоняет heartbeat от процесса другого пользователя") {
    let heartbeat = PowerHeartbeat(
        pid: 123,
        uid: 501,
        wantsClosedLidAwake: true,
        updatedAt: now
    )
    let candidate = PowerHeartbeatCandidate(
        fileName: PowerHeartbeat.url(for: 501).lastPathComponent,
        ownerUID: 501,
        permissions: 0o600,
        byteCount: 256,
        isRegularFile: true,
        heartbeat: heartbeat,
        processPath: "/Applications/Agent Awake.app/Contents/MacOS/AgentAwake",
        processUID: 502
    )

    try expect(
        !PowerHeartbeatValidator.accepts(candidate, now: now),
        "root-helper принял heartbeat чужого процесса"
    )
}

test("root-helper отклоняет небезопасный heartbeat-файл") {
    let heartbeat = PowerHeartbeat(
        pid: 123,
        uid: 501,
        wantsClosedLidAwake: true,
        updatedAt: now
    )
    func candidate(
        fileName: String = PowerHeartbeat.url(for: 501).lastPathComponent,
        ownerUID: UInt32 = 501,
        permissions: UInt16 = 0o600,
        byteCount: Int = 256,
        isRegularFile: Bool = true,
        processPath: String = "/Applications/Agent Awake.app/Contents/MacOS/AgentAwake"
    ) -> PowerHeartbeatCandidate {
        PowerHeartbeatCandidate(
            fileName: fileName,
            ownerUID: ownerUID,
            permissions: permissions,
            byteCount: byteCount,
            isRegularFile: isRegularFile,
            heartbeat: heartbeat,
            processPath: processPath,
            processUID: 501
        )
    }

    let unsafeCandidates = [
        candidate(fileName: "com.rodion.agentawake.fake.power-heartbeat"),
        candidate(ownerUID: 502),
        candidate(permissions: 0o644),
        candidate(byteCount: 4_097),
        candidate(isRegularFile: false),
        candidate(processPath: "/tmp/AgentAwake")
    ]

    try expect(
        unsafeCandidates.allSatisfy { !PowerHeartbeatValidator.accepts($0, now: now) },
        "root-helper принял небезопасный heartbeat-файл"
    )
}

test("root-helper принимает защищённый heartbeat установленного приложения") {
    let heartbeat = PowerHeartbeat(
        pid: 123,
        uid: 501,
        wantsClosedLidAwake: true,
        updatedAt: now
    )
    let candidate = PowerHeartbeatCandidate(
        fileName: PowerHeartbeat.url(for: 501).lastPathComponent,
        ownerUID: 501,
        permissions: 0o600,
        byteCount: 256,
        isRegularFile: true,
        heartbeat: heartbeat,
        processPath: PowerHeartbeatValidator.expectedProcessPath,
        processUID: 501
    )

    try expect(
        PowerHeartbeatValidator.accepts(candidate, now: now),
        "root-helper отклонил корректный heartbeat"
    )
}

func input(
    mode: SessionMode,
    activeAgentCount: Int = 0,
    agentsWereBusy: Bool = false,
    lidClosed: Bool = false,
    thermalLevel: ThermalLevel = .nominal,
    keepAwakeWithLidClosed: Bool = true,
    thermalProtectionEnabled: Bool = false,
    releaseAfterAgents: Bool = false,
    sleepAfterAgents: Bool = false
) -> PolicyInput {
    PolicyInput(
        mode: mode,
        now: now,
        activeAgentCount: activeAgentCount,
        agentsWereBusy: agentsWereBusy,
        lidClosed: lidClosed,
        thermalLevel: thermalLevel,
        keepAwakeWithLidClosed: keepAwakeWithLidClosed,
        thermalProtectionEnabled: thermalProtectionEnabled,
        releaseAfterAgents: releaseAfterAgents,
        sleepAfterAgents: sleepAfterAgents
    )
}

test("бессрочный режим удерживает Mac и закрытую крышку") {
    let decision = AwakePolicy.evaluate(input(mode: .indefinite))
    try expect(decision.shouldHoldAwake, "обычный сон не заблокирован")
    try expect(decision.shouldDisableClamshellSleep, "сон от крышки не заблокирован")
}

test("завершившийся таймер возвращает обычный сон") {
    let decision = AwakePolicy.evaluate(input(mode: .timed(until: now.addingTimeInterval(-1))))
    try expect(decision.stopReason == .timerFinished, "не распознано завершение таймера")
    try expect(!decision.shouldHoldAwake, "удержание осталось включено")
}

test("остаток таймера показывается в строке меню с округлением вверх") {
    let until = now.addingTimeInterval(14 * 60 + 1)
    try expect(
        TimedSession.remainingLabel(until: until, now: now) == "15m",
        "остаток таймера не показан как 15m"
    )
}

test("свой таймер принимает только целое число от 1 до 60 минут") {
    try expect(TimedSession.parseMinutes(" 1 ") == 1, "1 минута отклонена")
    try expect(TimedSession.parseMinutes("60") == 60, "60 минут отклонены")
    try expect(TimedSession.parseMinutes("0") == nil, "0 минут ошибочно принято")
    try expect(TimedSession.parseMinutes("61") == nil, "61 минута ошибочно принята")
    try expect(TimedSession.parseMinutes("1.5") == nil, "дробное число ошибочно принято")
}

test("закрытая крышка применяет экономию через 10 секунд и открытие сразу восстанавливает") {
    var action = DelayedLidAction(delay: 10)
    try expect(action.update(shouldApply: true, now: now) == .none, "экономия включилась сразу")
    try expect(
        action.update(shouldApply: true, now: now.addingTimeInterval(9)) == .none,
        "экономия включилась раньше 10 секунд"
    )
    try expect(
        action.update(shouldApply: false, now: now.addingTimeInterval(9.5)) == .none,
        "быстрое открытие ошибочно потребовало восстановления"
    )
    try expect(
        action.update(shouldApply: true, now: now.addingTimeInterval(20)) == .none,
        "повторное закрытие не начало новую задержку"
    )
    try expect(
        action.update(shouldApply: true, now: now.addingTimeInterval(30)) == .apply,
        "экономия не включилась через 10 секунд"
    )
    try expect(
        action.update(shouldApply: false, now: now.addingTimeInterval(31)) == .restore,
        "открытие не потребовало немедленного восстановления"
    )
}

test("звук подтверждает обе успешные операции один раз за закрытие крышки") {
    var notification = EnergySuccessNotification()

    try expect(
        !notification.update(
            lidClosed: true,
            dimmingEnabled: true,
            lowPowerEnabled: true,
            brightnessIsDimmed: true,
            lowPowerIsApplied: false
        ),
        "звук появился до подтверждения Low Power Mode"
    )
    try expect(
        notification.update(
            lidClosed: true,
            dimmingEnabled: true,
            lowPowerEnabled: true,
            brightnessIsDimmed: true,
            lowPowerIsApplied: true
        ),
        "звук не появился после успеха обеих операций"
    )
    try expect(
        !notification.update(
            lidClosed: true,
            dimmingEnabled: true,
            lowPowerEnabled: true,
            brightnessIsDimmed: true,
            lowPowerIsApplied: true
        ),
        "звук повторился при той же закрытой крышке"
    )
    try expect(
        !notification.update(
            lidClosed: false,
            dimmingEnabled: true,
            lowPowerEnabled: true,
            brightnessIsDimmed: false,
            lowPowerIsApplied: false
        ),
        "открытие крышки ошибочно вызвало звук"
    )
    try expect(
        !notification.update(
            lidClosed: true,
            dimmingEnabled: false,
            lowPowerEnabled: true,
            brightnessIsDimmed: false,
            lowPowerIsApplied: true
        ),
        "звук появился при выключенном затемнении"
    )
    _ = notification.update(
        lidClosed: false,
        dimmingEnabled: true,
        lowPowerEnabled: true,
        brightnessIsDimmed: false,
        lowPowerIsApplied: false
    )
    try expect(
        !notification.update(
            lidClosed: true,
            dimmingEnabled: true,
            lowPowerEnabled: false,
            brightnessIsDimmed: true,
            lowPowerIsApplied: false
        ),
        "звук появился при выключенном Low Power Mode"
    )
    try expect(
        notification.update(
            lidClosed: true,
            dimmingEnabled: true,
            lowPowerEnabled: true,
            brightnessIsDimmed: true,
            lowPowerIsApplied: true
        ),
        "уведомление не перевзвелоcь после открытия крышки"
    )
}

test("Purr подтверждает активную защиту сна через секунду и один раз за закрытие") {
    var notification = SleepProtectionNotification(delay: 1)

    try expect(
        !notification.update(lidClosed: true, protectionActive: false, now: now),
        "звук появился без активной защиты сна"
    )
    try expect(
        !notification.update(lidClosed: true, protectionActive: true, now: now),
        "звук появился сразу после закрытия"
    )
    try expect(
        !notification.update(
            lidClosed: true,
            protectionActive: true,
            now: now.addingTimeInterval(0.9)
        ),
        "звук появился раньше одной секунды"
    )
    try expect(
        notification.update(
            lidClosed: true,
            protectionActive: true,
            now: now.addingTimeInterval(1)
        ),
        "звук не подтвердил защиту через одну секунду"
    )
    try expect(
        !notification.update(
            lidClosed: true,
            protectionActive: true,
            now: now.addingTimeInterval(2)
        ),
        "звук повторился при той же закрытой крышке"
    )
    try expect(
        !notification.update(
            lidClosed: false,
            protectionActive: true,
            now: now.addingTimeInterval(3)
        ),
        "открытие крышки ошибочно вызвало звук"
    )
    try expect(
        !notification.update(
            lidClosed: true,
            protectionActive: true,
            now: now.addingTimeInterval(4)
        ),
        "повторное закрытие не запустило новую задержку"
    )
    try expect(
        notification.update(
            lidClosed: true,
            protectionActive: true,
            now: now.addingTimeInterval(5)
        ),
        "уведомление не перевзвелось после открытия крышки"
    )
}

test("режим агентов без задач остаётся вооружённым, но разрешает сон") {
    let decision = AwakePolicy.evaluate(
        input(mode: .agents, activeAgentCount: 0, agentsWereBusy: false, releaseAfterAgents: true)
    )
    try expect(!decision.shouldHoldAwake, "Mac удерживается без активных задач")
    try expect(!decision.shouldEndSession, "наблюдение за новыми задачами выключилось")
}

test("после агентов можно только разрешить обычный сон") {
    let decision = AwakePolicy.evaluate(
        input(mode: .agents, activeAgentCount: 0, agentsWereBusy: true, releaseAfterAgents: true)
    )
    try expect(decision.stopReason == .agentsFinished, "окончание агентов не распознано")
    try expect(!decision.shouldEndSession, "наблюдение за следующей задачей выключилось")
    try expect(!decision.shouldSleepNow, "Mac ошибочно усыпляется немедленно")
}

test("новая задача повторно включает постоянное наблюдение") {
    let decision = AwakePolicy.evaluate(
        input(mode: .agents, activeAgentCount: 1, agentsWereBusy: false, releaseAfterAgents: true)
    )
    try expect(decision.shouldHoldAwake, "новая задача не включила удержание")
    try expect(decision.shouldDisableClamshellSleep, "новая задача не включила защиту крышки")
    try expect(!decision.shouldEndSession, "наблюдение завершилось во время задачи")
}

test("после агентов можно немедленно усыпить Mac") {
    let decision = AwakePolicy.evaluate(
        input(mode: .agents, activeAgentCount: 0, agentsWereBusy: true, sleepAfterAgents: true)
    )
    try expect(decision.shouldSleepNow, "немедленный сон не запрошен")
}

test("опасный нагрев закрытого Mac выключает любое удержание") {
    let decision = AwakePolicy.evaluate(
        input(
            mode: .indefinite,
            lidClosed: true,
            thermalLevel: .serious,
            thermalProtectionEnabled: true
        )
    )
    try expect(decision.stopReason == .thermalSafety, "защита не сработала")
    try expect(!decision.shouldHoldAwake, "обычное удержание осталось включено")
    try expect(!decision.shouldDisableClamshellSleep, "удержание крышки осталось включено")
    try expect(decision.shouldSleepNow, "защитный сон не запрошен")
}

test("опасный нагрев с открытой крышкой не вызывает защитный сон") {
    let decision = AwakePolicy.evaluate(
        input(
            mode: .indefinite,
            lidClosed: false,
            thermalLevel: .critical,
            thermalProtectionEnabled: true
        )
    )
    try expect(decision.shouldHoldAwake, "защита ошибочно сработала с открытой крышкой")
}

test("Codex активен между task_started и task_complete") {
    let lines = [
        #"{"type":"event_msg","payload":{"type":"task_started"}}"#,
        #"{"type":"response_item","payload":{"type":"custom_tool_call"}}"#
    ].map { Data($0.utf8) }
    try expect(AgentLogClassifier.codexIsActive(lines: lines), "активный Codex не распознан")
}

test("Codex неактивен после task_complete") {
    let lines = [
        #"{"type":"event_msg","payload":{"type":"task_started"}}"#,
        #"{"type":"event_msg","payload":{"type":"task_complete"}}"#
    ].map { Data($0.utf8) }
    try expect(!AgentLogClassifier.codexIsActive(lines: lines), "завершённый Codex остался активным")
}

test("пользовательский запрос запускает Claude Code") {
    let lines = [
        #"{"type":"user","message":{"content":"Сделай задачу"}}"#,
        #"{"type":"assistant","message":{"stop_reason":"tool_use"}}"#
    ].map { Data($0.utf8) }
    try expect(AgentLogClassifier.claudeIsActive(lines: lines), "активный Claude Code не распознан")
}

test("tool_result не запускает завершённую Claude-сессию заново") {
    let lines = [
        #"{"type":"assistant","message":{"stop_reason":"end_turn"}}"#,
        #"{"type":"user","message":{"content":[{"type":"tool_result"}]}}"#
    ].map { Data($0.utf8) }
    try expect(!AgentLogClassifier.claudeIsActive(lines: lines), "tool_result принят за новый запрос")
}

test("end_turn завершает Claude Code") {
    let lines = [
        #"{"type":"user","message":{"content":"Сделай задачу"}}"#,
        #"{"type":"assistant","message":{"stop_reason":"end_turn"}}"#
    ].map { Data($0.utf8) }
    try expect(!AgentLogClassifier.claudeIsActive(lines: lines), "завершённый Claude остался активным")
}

test("длинный журнал Codex не скрывает активную задачу") {
    let temporaryHome = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-awake-codex-test-\(UUID().uuidString)")
    let sessions = temporaryHome.appendingPathComponent(".codex/sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryHome) }

    let file = sessions.appendingPathComponent("long.jsonl")
    var data = Data(#"{"type":"event_msg","payload":{"type":"task_started"}}"#.utf8)
    data.append(0x0A)
    let filler = Data(#"{"type":"response_item","payload":{"type":"custom_tool_call_output"}}"#.utf8)
    for _ in 0..<12_000 {
        data.append(filler)
        data.append(0x0A)
    }
    try data.write(to: file)

    let snapshot = AgentActivityDetector(homeURL: temporaryHome).snapshot(now: Date())
    try expect(snapshot.codexActiveCount == 1, "длинная активная Codex-задача потеряна")
}

test("длинный журнал Claude не скрывает активную задачу") {
    let temporaryHome = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-awake-claude-test-\(UUID().uuidString)")
    let projects = temporaryHome.appendingPathComponent(".claude/projects/project", isDirectory: true)
    try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryHome) }

    let file = projects.appendingPathComponent("long.jsonl")
    var data = Data(#"{"type":"user","message":{"content":"Сделай задачу"}}"#.utf8)
    data.append(0x0A)
    let filler = Data(#"{"type":"user","message":{"content":[{"type":"tool_result"}]}}"#.utf8)
    for _ in 0..<12_000 {
        data.append(filler)
        data.append(0x0A)
    }
    try data.write(to: file)

    let snapshot = AgentActivityDetector(homeURL: temporaryHome).snapshot(now: Date())
    try expect(snapshot.claudeActiveCount == 1, "длинная активная Claude-задача потеряна")
}

test("служебные observer-сессии Claude Memory не считаются агентами") {
    let temporaryHome = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-awake-observer-test-\(UUID().uuidString)")
    let observerDirectory = temporaryHome
        .appendingPathComponent(".claude/projects/-Users-Test--claude-mem-observer-sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: observerDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryHome) }

    let file = observerDirectory.appendingPathComponent("observer.jsonl")
    let activeLine = Data(#"{"type":"user","message":{"content":"observer event"}}"#.utf8)
    try activeLine.write(to: file)

    let snapshot = AgentActivityDetector(homeURL: temporaryHome).snapshot(now: Date())
    try expect(snapshot.claudeActiveCount == 0, "observer ошибочно принят за Claude Code")
}

test("незавершённый старый журнал Claude не считается текущей задачей") {
    let temporaryHome = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-awake-stale-claude-test-\(UUID().uuidString)")
    let projects = temporaryHome.appendingPathComponent(".claude/projects/project", isDirectory: true)
    try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryHome) }

    let file = projects.appendingPathComponent("stale.jsonl")
    let activeLine = Data(#"{"type":"user","message":{"content":"Сделай задачу"}}"#.utf8)
    try activeLine.write(to: file)
    try FileManager.default.setAttributes(
        [.modificationDate: Date().addingTimeInterval(-31 * 60)],
        ofItemAtPath: file.path
    )

    let snapshot = AgentActivityDetector(homeURL: temporaryHome).snapshot(now: Date())
    try expect(snapshot.claudeActiveCount == 0, "старый незавершённый журнал остался активным")
}

test("нормальная зарядка показывает блок, фактическую мощность и честный предел кабеля") {
    let presentation = ChargingDiagnostics.presentation(
        for: ChargingTelemetry(
            externalPowerConnected: true,
            adapterWatts: 96,
            inputWatts: 42.4,
            batteryWatts: 8,
            slowChargingDetected: false
        )
    )

    try expect(
        presentation.menuLines == [
            "Блок питания: 96 Вт",
            "Mac получает: около 42 Вт",
            "Кабель/соединение: ≥42 Вт подтверждено · номинал неизвестен",
            "Зарядка: питание в норме"
        ],
        "информация о нормальной зарядке показана неверно: \(presentation.menuLines)"
    )
    try expect(!presentation.shouldWarn, "нормальная зарядка ошибочно вызвала предупреждение")
}

test("сигнал Slow Charger предупреждает проверить блок или кабель") {
    let presentation = ChargingDiagnostics.presentation(
        for: ChargingTelemetry(
            externalPowerConnected: true,
            adapterWatts: 30,
            inputWatts: 27.6,
            batteryWatts: 4,
            slowChargingDetected: true
        )
    )

    try expect(presentation.shouldWarn, "Slow Charger не включил предупреждение")
    try expect(
        presentation.menuLines.last
            == "⚠︎ Зарядка медленная · проверьте блок или кабель",
        "причина медленной зарядки показана неверно"
    )
}

test("разряд батареи от сети означает нехватку питания под нагрузкой") {
    let presentation = ChargingDiagnostics.presentation(
        for: ChargingTelemetry(
            externalPowerConnected: true,
            adapterWatts: 60,
            inputWatts: 58,
            batteryWatts: -6.2,
            slowChargingDetected: false
        )
    )

    try expect(presentation.shouldWarn, "разряд от сети не включил предупреждение")
    try expect(
        presentation.menuLines.last
            == "⚠︎ Питания не хватает под текущей нагрузкой",
        "разряд от сети получил неверный диагноз"
    )
}

test("неполные данные macOS не превращаются в ложный диагноз") {
    let presentation = ChargingDiagnostics.presentation(
        for: ChargingTelemetry(
            externalPowerConnected: true,
            adapterWatts: nil,
            inputWatts: nil,
            batteryWatts: nil,
            slowChargingDetected: false
        )
    )

    try expect(!presentation.shouldWarn, "неизвестные данные ошибочно вызвали тревогу")
    try expect(
        presentation.menuLines == [
            "Блок питания: не удалось определить",
            "Mac получает: не удалось определить",
            "Кабель/соединение: номинал не сообщается macOS",
            "Зарядка: недостаточно данных"
        ],
        "неизвестные данные скрыты или выданы за норму"
    )
}

test("Sosumi предупреждает после 10 секунд проблемы и не повторяется до восстановления") {
    var notification = ChargingWarningNotification(delay: 10)

    try expect(
        !notification.update(problemDetected: true, now: now),
        "звук появился сразу"
    )
    try expect(
        !notification.update(problemDetected: true, now: now.addingTimeInterval(9)),
        "звук появился раньше 10 секунд"
    )
    try expect(
        notification.update(problemDetected: true, now: now.addingTimeInterval(10)),
        "звук не появился после 10 секунд проблемы"
    )
    try expect(
        !notification.update(problemDetected: true, now: now.addingTimeInterval(20)),
        "звук повторился при той же проблеме"
    )
    try expect(
        !notification.update(problemDetected: false, now: now.addingTimeInterval(21)),
        "восстановление питания ошибочно вызвало звук"
    )
    try expect(
        !notification.update(problemDetected: true, now: now.addingTimeInterval(22)),
        "новая проблема не начала новую задержку"
    )
    try expect(
        notification.update(problemDetected: true, now: now.addingTimeInterval(32)),
        "уведомление не перевзвелось после восстановления"
    )
}

print("Tests: \(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
