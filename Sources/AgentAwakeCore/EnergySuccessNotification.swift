public struct EnergySuccessNotification {
    private var hasNotifiedForCurrentClosure = false

    public init() {}

    public mutating func update(
        lidClosed: Bool,
        dimmingEnabled: Bool,
        lowPowerEnabled: Bool,
        brightnessIsDimmed: Bool,
        lowPowerIsApplied: Bool
    ) -> Bool {
        guard lidClosed else {
            hasNotifiedForCurrentClosure = false
            return false
        }

        guard !hasNotifiedForCurrentClosure,
              dimmingEnabled,
              lowPowerEnabled,
              brightnessIsDimmed,
              lowPowerIsApplied else {
            return false
        }

        hasNotifiedForCurrentClosure = true
        return true
    }
}
