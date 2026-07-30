import Foundation

public enum SessionMode: Equatable {
    case off
    case timed(until: Date)
    case indefinite
    case agents
}

public enum ThermalLevel: Int, CaseIterable, Comparable {
    case nominal = 0
    case fair = 1
    case serious = 2
    case critical = 3

    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var isDangerous: Bool {
        self >= .serious
    }

    public var displayName: String {
        switch self {
        case .nominal: return "Норма"
        case .fair: return "Повышен"
        case .serious: return "Опасный"
        case .critical: return "Критический"
        }
    }
}

public struct PolicyInput {
    public let mode: SessionMode
    public let now: Date
    public let activeAgentCount: Int
    public let agentsWereBusy: Bool
    public let lidClosed: Bool
    public let thermalLevel: ThermalLevel
    public let keepAwakeWithLidClosed: Bool
    public let thermalProtectionEnabled: Bool
    public let releaseAfterAgents: Bool
    public let sleepAfterAgents: Bool

    public init(
        mode: SessionMode,
        now: Date,
        activeAgentCount: Int,
        agentsWereBusy: Bool,
        lidClosed: Bool,
        thermalLevel: ThermalLevel,
        keepAwakeWithLidClosed: Bool,
        thermalProtectionEnabled: Bool,
        releaseAfterAgents: Bool,
        sleepAfterAgents: Bool
    ) {
        self.mode = mode
        self.now = now
        self.activeAgentCount = activeAgentCount
        self.agentsWereBusy = agentsWereBusy
        self.lidClosed = lidClosed
        self.thermalLevel = thermalLevel
        self.keepAwakeWithLidClosed = keepAwakeWithLidClosed
        self.thermalProtectionEnabled = thermalProtectionEnabled
        self.releaseAfterAgents = releaseAfterAgents
        self.sleepAfterAgents = sleepAfterAgents
    }
}

public enum PolicyStopReason: Equatable {
    case none
    case timerFinished
    case agentsFinished
    case thermalSafety
}

public struct PolicyDecision: Equatable {
    public let shouldHoldAwake: Bool
    public let shouldDisableClamshellSleep: Bool
    public let shouldEndSession: Bool
    public let shouldSleepNow: Bool
    public let stopReason: PolicyStopReason

    public init(
        shouldHoldAwake: Bool,
        shouldDisableClamshellSleep: Bool,
        shouldEndSession: Bool,
        shouldSleepNow: Bool,
        stopReason: PolicyStopReason
    ) {
        self.shouldHoldAwake = shouldHoldAwake
        self.shouldDisableClamshellSleep = shouldDisableClamshellSleep
        self.shouldEndSession = shouldEndSession
        self.shouldSleepNow = shouldSleepNow
        self.stopReason = stopReason
    }
}

public enum AwakePolicy {
    public static func evaluate(_ input: PolicyInput) -> PolicyDecision {
        guard input.mode != .off else {
            return stopped(reason: .none, sleepNow: false)
        }

        if input.thermalProtectionEnabled,
           input.lidClosed,
           input.thermalLevel.isDangerous {
            return stopped(reason: .thermalSafety, sleepNow: true)
        }

        if case let .timed(until) = input.mode, until <= input.now {
            return stopped(reason: .timerFinished, sleepNow: false)
        }

        if input.mode == .agents {
            if input.activeAgentCount > 0 {
                return held(keepAwakeWithLidClosed: input.keepAwakeWithLidClosed)
            }

            if input.agentsWereBusy,
               input.releaseAfterAgents || input.sleepAfterAgents {
                return PolicyDecision(
                    shouldHoldAwake: false,
                    shouldDisableClamshellSleep: false,
                    shouldEndSession: false,
                    shouldSleepNow: input.sleepAfterAgents,
                    stopReason: .agentsFinished
                )
            }

            if !input.agentsWereBusy {
                return PolicyDecision(
                    shouldHoldAwake: false,
                    shouldDisableClamshellSleep: false,
                    shouldEndSession: false,
                    shouldSleepNow: false,
                    stopReason: .none
                )
            }
        }

        return held(keepAwakeWithLidClosed: input.keepAwakeWithLidClosed)
    }

    private static func held(keepAwakeWithLidClosed: Bool) -> PolicyDecision {
        PolicyDecision(
            shouldHoldAwake: true,
            shouldDisableClamshellSleep: keepAwakeWithLidClosed,
            shouldEndSession: false,
            shouldSleepNow: false,
            stopReason: .none
        )
    }

    private static func stopped(reason: PolicyStopReason, sleepNow: Bool) -> PolicyDecision {
        PolicyDecision(
            shouldHoldAwake: false,
            shouldDisableClamshellSleep: false,
            shouldEndSession: reason != .none,
            shouldSleepNow: sleepNow,
            stopReason: reason
        )
    }
}
