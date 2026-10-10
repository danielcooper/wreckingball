import Foundation

enum BackgroundKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case gradient, solid, image

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gradient: "Gradient"
        case .solid: "Colour"
        case .image: "Image"
        }
    }
}

enum GradientKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case linear, radial, aurora

    var id: String { rawValue }

    var label: String {
        switch self {
        case .linear: "Linear"
        case .radial: "Radial"
        case .aurora: "Aurora"
        }
    }
}

struct BackgroundSettings: Codable, Equatable, Sendable {
    var kind = BackgroundKind.gradient

    var gradientKind = GradientKind.linear
    /// Two to four colour stops.
    var colors = BackgroundPreset.twilight.colors
    /// Direction of a linear gradient in degrees; 0 runs left to right, 90 bottom to top.
    var angle = 45.0

    var solidColor = RGBAColor(red: 0.11, green: 0.11, blue: 0.14)

    var imagePath: String?
    /// Blur radius on a 1080p canvas.
    var imageBlur = 0.0
    /// 0 leaves the image as is; 1 is black.
    var imageDim = 0.0

    /// 0 to 1.
    var vignette = 0.0
    /// 0 to 1.
    var grain = 0.0

    static let colorStopRange = 2...4

    mutating func apply(_ preset: BackgroundPreset) {
        kind = .gradient
        gradientKind = preset.kind
        colors = preset.colors
        angle = preset.angle
    }

    func matches(_ preset: BackgroundPreset) -> Bool {
        kind == .gradient && gradientKind == preset.kind && colors == preset.colors && (preset.kind != .linear || angle == preset.angle)
    }
}

extension BackgroundSettings {
    init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        kind = value(.kind, kind)
        gradientKind = value(.gradientKind, gradientKind)
        colors = value(.colors, colors)
        if !Self.colorStopRange.contains(colors.count) {
            colors = BackgroundPreset.twilight.colors
        }
        angle = value(.angle, angle)
        solidColor = value(.solidColor, solidColor)
        imagePath = value(.imagePath, imagePath)
        imageBlur = value(.imageBlur, imageBlur)
        imageDim = value(.imageDim, imageDim)
        vignette = value(.vignette, vignette)
        grain = value(.grain, grain)
    }
}

struct BackgroundPreset: Identifiable, Sendable {
    let name: String
    let kind: GradientKind
    let colors: [RGBAColor]
    var angle = 45.0

    var id: String { name }

    private static func rgb(_ hex: UInt32) -> RGBAColor {
        RGBAColor(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// The original Wreckingball background.
    static let twilight = BackgroundPreset(name: "Twilight", kind: .linear, colors: [
        RGBAColor(red: 0.09, green: 0.11, blue: 0.22), RGBAColor(red: 0.36, green: 0.22, blue: 0.50),
    ])

    static let all: [BackgroundPreset] = [
        twilight,
        BackgroundPreset(name: "Midnight", kind: .linear, colors: [rgb(0x0F0C29), rgb(0x302B63), rgb(0x24243E)], angle: 90),
        BackgroundPreset(name: "Ocean", kind: .linear, colors: [rgb(0x0F2027), rgb(0x203A43), rgb(0x2C5364)], angle: 30),
        BackgroundPreset(name: "Graphite", kind: .radial, colors: [rgb(0x4B4E57), rgb(0x1C1D22)]),
        BackgroundPreset(name: "Sunset", kind: .linear, colors: [rgb(0xFF5F6D), rgb(0xFFC371)], angle: 60),
        BackgroundPreset(name: "Candy", kind: .linear, colors: [rgb(0xF857A6), rgb(0xFF5858)], angle: 20),
        BackgroundPreset(name: "Forest", kind: .linear, colors: [rgb(0x134E5E), rgb(0x71B280)], angle: 60),
        BackgroundPreset(name: "Mist", kind: .linear, colors: [rgb(0xE0EAFC), rgb(0xCFDEF3)], angle: 90),
        BackgroundPreset(name: "Aurora", kind: .aurora, colors: [rgb(0x0B1026), rgb(0x1FD1A5), rgb(0x5B5BF0), rgb(0xB14FE0)]),
        BackgroundPreset(name: "Lagoon", kind: .aurora, colors: [rgb(0x08263A), rgb(0x00B4D8), rgb(0x48CAE4), rgb(0x90E0EF)]),
        BackgroundPreset(name: "Ember", kind: .aurora, colors: [rgb(0x1A0B0B), rgb(0xFF6B35), rgb(0xF7C59F), rgb(0xD7263D)]),
        BackgroundPreset(name: "Pastel", kind: .aurora, colors: [rgb(0xFDF6F0), rgb(0xFFC8DD), rgb(0xBDE0FE), rgb(0xCDB4DB)]),
    ]
}
