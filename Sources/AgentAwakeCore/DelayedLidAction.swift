import Foundation

public enum DelayedLidCommand: Equatable {
    case none
    case apply
    case restore
}

public struct DelayedLidAction {
    private enum Phase {
        case idle
        case pending(since: Date)
        case applied
    }

    private let delay: TimeInterval
    private var phase: Phase

    public init(delay: TimeInterval = 10, initiallyApplied: Bool = false) {
        self.delay = delay
        self.phase = initiallyApplied ? .applied : .idle
    }

    public mutating func update(shouldApply: Bool, now: Date = Date()) -> DelayedLidCommand {
        guard shouldApply else {
            switch phase {
            case .applied:
                phase = .idle
                return .restore
            case .pending:
                phase = .idle
                return .none
            case .idle:
                return .none
            }
        }

        switch phase {
        case .idle:
            phase = .pending(since: now)
            return .none
        case let .pending(since):
            guard now.timeIntervalSince(since) >= delay else { return .none }
            phase = .applied
            return .apply
        case .applied:
            return .none
        }
    }
}
