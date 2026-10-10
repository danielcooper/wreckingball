import Foundation

/// Actions that can be triggered by a shortcut or a `wreckingball://` URL.
enum Command: Equatable, Sendable {
    case toggleRecording
    case startRecording
    case stopRecording
    case pin(Int)
    case nextWindow
    case previousWindow
    case toggleCamera
    case toggleKeystrokes

    static let scheme = "wreckingball"

    /// Parses URLs such as `wreckingball://pin/2` or `wreckingball://record/toggle`.
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        let parts = ([url.host()] + url.pathComponents)
            .compactMap { $0?.lowercased() }
            .filter { !$0.isEmpty && $0 != "/" }
        guard let group = parts.first else { return nil }
        let argument = parts.count > 1 ? parts[1] : nil

        switch (group, argument) {
        case ("record", "toggle"), ("record", nil): self = .toggleRecording
        case ("record", "start"): self = .startRecording
        case ("record", "stop"): self = .stopRecording
        case ("window", "next"): self = .nextWindow
        case ("window", "previous"), ("window", "prev"): self = .previousWindow
        case ("camera", "toggle"), ("camera", nil): self = .toggleCamera
        case ("keys", "toggle"), ("keys", nil): self = .toggleKeystrokes
        case ("pin", let slot?):
            guard let number = Int(slot), (1...Pin.maxCount).contains(number) else { return nil }
            self = .pin(number)
        default: return nil
        }
    }

    /// The URLs shown in Settings for Stream Deck setup.
    static let documentation: [(url: String, action: String)] = [
        ("wreckingball://record/toggle", "Start or stop recording"),
        ("wreckingball://record/start", "Start recording"),
        ("wreckingball://record/stop", "Stop recording"),
        ("wreckingball://pin/1", "Present pinned window 1 (up to 9)"),
        ("wreckingball://window/next", "Present the next window"),
        ("wreckingball://window/previous", "Present the previous window"),
        ("wreckingball://camera/toggle", "Show or hide the camera"),
        ("wreckingball://keys/toggle", "Show or hide keystrokes"),
    ]
}
