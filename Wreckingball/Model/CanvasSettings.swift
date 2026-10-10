import CoreGraphics
import Foundation

enum Resolution: String, Codable, CaseIterable, Identifiable, Sendable {
    case hd720, hd1080, qhd1440, uhd2160

    var id: String { rawValue }

    var size: CGSize {
        switch self {
        case .hd720: CGSize(width: 1280, height: 720)
        case .hd1080: CGSize(width: 1920, height: 1080)
        case .qhd1440: CGSize(width: 2560, height: 1440)
        case .uhd2160: CGSize(width: 3840, height: 2160)
        }
    }

    var label: String {
        switch self {
        case .hd720: "720p"
        case .hd1080: "1080p"
        case .qhd1440: "1440p"
        case .uhd2160: "4K"
        }
    }
}

enum VideoCodec: String, Codable, CaseIterable, Identifiable, Sendable {
    case h264, hevc

    var id: String { rawValue }

    var label: String {
        switch self {
        case .h264: "H.264"
        case .hevc: "HEVC"
        }
    }
}

struct CanvasSettings: Codable, Equatable, Sendable {
    var resolution = Resolution.hd1080
    var fps = 30
    var codec = VideoCodec.h264
    var background = BackgroundSettings()
    var outputFolder: String?

    /// Margin around the presented window, as a fraction of canvas height.
    var windowPadding = 0.06
    /// Corner radius of the presented window, in pixels on a 1080p canvas.
    var windowCornerRadius = 16.0
    var windowShadow = true

    var cameraEnabled = true
    var cameraShape = CameraShape.circle
    /// Camera height as a fraction of canvas height.
    var cameraSize = 0.28
    /// Camera centre, normalised to the canvas with a top-left origin.
    var cameraCenter = CGPoint(x: 0.88, y: 0.8)
    var cameraMirrored = true

    var cameraDeviceID: String?
    var micDeviceID: String?
    /// Bring the presented window's app to the front when switching.
    var activateOnSwitch = true

    /// Show the keys being pressed on the canvas.
    var keystrokesEnabled = false
    var keystrokeMode = KeystrokeMode.shortcuts
    /// Centre of the keystroke pill, normalised to the canvas with a top-left origin.
    var keystrokeCenter = CGPoint(x: 0.5, y: 0.89)
    var keystrokeStyle = KeystrokeStyle()

    var canvasSize: CGSize { resolution.size }

    /// The largest area the presented window may occupy, in canvas pixels.
    var windowBox: CGSize {
        let padding = windowPadding * canvasSize.height
        return CGSize(width: canvasSize.width - padding * 2, height: canvasSize.height - padding * 2)
    }

    private static let defaultsKey = "canvasSettings"

    static func load() -> CanvasSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(CanvasSettings.self, from: data)
        else { return CanvasSettings() }
        return settings
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

enum KeystrokeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Only combinations with ⌘ or ⌃.
    case shortcuts
    /// Shortcuts plus everything typed.
    case allKeys

    var id: String { rawValue }

    var label: String {
        switch self {
        case .shortcuts: "Shortcuts only"
        case .allKeys: "All keys"
        }
    }
}

extension CanvasSettings {
    private enum LegacyKeys: String, CodingKey {
        case backgroundPath
    }

    /// Fields missing from older saved settings keep their defaults instead of failing the whole decode.
    init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        resolution = value(.resolution, resolution)
        fps = value(.fps, fps)
        codec = value(.codec, codec)
        background = value(.background, background)
        // Before backgrounds had their own settings, only an image path was stored.
        if !container.contains(.background),
           let legacy = try? decoder.container(keyedBy: LegacyKeys.self),
           let path = try? legacy.decodeIfPresent(String.self, forKey: .backgroundPath) {
            background.kind = .image
            background.imagePath = path
        }
        outputFolder = value(.outputFolder, outputFolder)
        windowPadding = value(.windowPadding, windowPadding)
        windowCornerRadius = value(.windowCornerRadius, windowCornerRadius)
        windowShadow = value(.windowShadow, windowShadow)
        cameraEnabled = value(.cameraEnabled, cameraEnabled)
        cameraShape = value(.cameraShape, cameraShape)
        cameraSize = value(.cameraSize, cameraSize)
        cameraCenter = value(.cameraCenter, cameraCenter)
        cameraMirrored = value(.cameraMirrored, cameraMirrored)
        cameraDeviceID = value(.cameraDeviceID, cameraDeviceID)
        micDeviceID = value(.micDeviceID, micDeviceID)
        activateOnSwitch = value(.activateOnSwitch, activateOnSwitch)
        keystrokesEnabled = value(.keystrokesEnabled, keystrokesEnabled)
        keystrokeMode = value(.keystrokeMode, keystrokeMode)
        keystrokeCenter = value(.keystrokeCenter, keystrokeCenter)
        keystrokeStyle = value(.keystrokeStyle, keystrokeStyle)
    }
}
