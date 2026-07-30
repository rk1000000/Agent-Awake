import CoreGraphics
import Darwin
import Foundation

final class BuiltInDisplayBrightnessController {
    enum BrightnessError: LocalizedError {
        case frameworkUnavailable
        case builtInDisplayUnavailable
        case operationFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .frameworkUnavailable:
                return "macOS не предоставила управление яркостью"
            case .builtInDisplayUnavailable:
                return "Встроенный экран не найден"
            case let .operationFailed(code):
                return "Не удалось изменить яркость встроенного экрана (\(code))"
            }
        }
    }

    private typealias GetBrightness = @convention(c) (
        CGDirectDisplayID,
        UnsafeMutablePointer<Float>
    ) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let frameworkHandle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        RTLD_LAZY
    )
    private static let getBrightness: GetBrightness? = {
        guard let frameworkHandle,
              let symbol = dlsym(frameworkHandle, "DisplayServicesGetBrightness") else {
            return nil
        }
        return unsafeBitCast(symbol, to: GetBrightness.self)
    }()
    private static let setBrightness: SetBrightness? = {
        guard let frameworkHandle,
              let symbol = dlsym(frameworkHandle, "DisplayServicesSetBrightness") else {
            return nil
        }
        return unsafeBitCast(symbol, to: SetBrightness.self)
    }()

    private lazy var displayID: CGDirectDisplayID? = Self.findBuiltInDisplay()

    func currentBrightness() throws -> Float {
        guard let getBrightness = Self.getBrightness else {
            throw BrightnessError.frameworkUnavailable
        }
        guard let displayID else {
            throw BrightnessError.builtInDisplayUnavailable
        }
        var value: Float = 0
        let result = getBrightness(displayID, &value)
        guard result == 0 else { throw BrightnessError.operationFailed(result) }
        return value
    }

    func setBrightness(_ value: Float) throws {
        guard let setBrightness = Self.setBrightness else {
            throw BrightnessError.frameworkUnavailable
        }
        guard let displayID else {
            throw BrightnessError.builtInDisplayUnavailable
        }
        let result = setBrightness(displayID, min(1, max(0, value)))
        guard result == 0 else { throw BrightnessError.operationFailed(result) }
    }

    private static func findBuiltInDisplay() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.first { CGDisplayIsBuiltin($0) != 0 }
    }
}
