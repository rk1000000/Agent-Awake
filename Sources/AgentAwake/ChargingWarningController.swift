import AppKit
import AgentAwakeCore
import OSLog

final class ChargingWarningController {
    private let sound = NSSound(
        contentsOfFile: "/System/Library/Sounds/Sosumi.aiff",
        byReference: true
    )
    private let logger = Logger(subsystem: "com.rodion.agentawake", category: "charging")
    private var notification = ChargingWarningNotification(delay: 10)

    func update(problemDetected: Bool) {
        guard notification.update(problemDetected: problemDetected) else { return }

        guard let sound else {
            NSSound.beep()
            logger.notice("charging warning fallback sound requested")
            return
        }
        sound.stop()
        sound.currentTime = 0
        if sound.play() {
            logger.notice("charging warning Sosumi played after persistent power problem")
        } else {
            NSSound.beep()
            logger.notice("charging warning fallback sound requested after Sosumi playback failure")
        }
    }
}
