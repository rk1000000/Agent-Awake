public struct ChargingTelemetry: Equatable {
    public let externalPowerConnected: Bool
    public let adapterWatts: Int?
    public let inputWatts: Double?
    public let batteryWatts: Double?
    public let slowChargingDetected: Bool

    public init(
        externalPowerConnected: Bool,
        adapterWatts: Int?,
        inputWatts: Double?,
        batteryWatts: Double?,
        slowChargingDetected: Bool
    ) {
        self.externalPowerConnected = externalPowerConnected
        self.adapterWatts = adapterWatts
        self.inputWatts = inputWatts
        self.batteryWatts = batteryWatts
        self.slowChargingDetected = slowChargingDetected
    }
}

public struct ChargingPresentation: Equatable {
    public let menuLines: [String]
    public let shouldWarn: Bool

    public init(menuLines: [String], shouldWarn: Bool) {
        self.menuLines = menuLines
        self.shouldWarn = shouldWarn
    }
}

public enum ChargingDiagnostics {
    public static func presentation(for telemetry: ChargingTelemetry) -> ChargingPresentation {
        guard telemetry.externalPowerConnected else {
            return ChargingPresentation(menuLines: [], shouldWarn: false)
        }

        let adapter = telemetry.adapterWatts.map { "\($0) Вт" } ?? "не удалось определить"
        let input = telemetry.inputWatts.map { roundedWatts($0) }
        let inputDescription = input.map { "около \($0) Вт" } ?? "не удалось определить"
        let cableDescription = input.map {
            "≥\($0) Вт подтверждено · номинал неизвестен"
        } ?? "номинал не сообщается macOS"
        let batteryIsDischarging = (telemetry.batteryWatts ?? 0) < -1
        let hasPowerMeasurement = telemetry.adapterWatts != nil
            || telemetry.inputWatts != nil
            || telemetry.batteryWatts != nil
        let status: String
        if telemetry.slowChargingDetected {
            status = "⚠︎ Зарядка медленная · проверьте блок или кабель"
        } else if batteryIsDischarging {
            status = "⚠︎ Питания не хватает под текущей нагрузкой"
        } else if !hasPowerMeasurement {
            status = "Зарядка: недостаточно данных"
        } else {
            status = "Зарядка: питание в норме"
        }

        return ChargingPresentation(
            menuLines: [
                "Блок питания: \(adapter)",
                "Mac получает: \(inputDescription)",
                "Кабель/соединение: \(cableDescription)",
                status
            ],
            shouldWarn: telemetry.slowChargingDetected || batteryIsDischarging
        )
    }

    private static func roundedWatts(_ value: Double) -> Int {
        Int(value.rounded())
    }
}
