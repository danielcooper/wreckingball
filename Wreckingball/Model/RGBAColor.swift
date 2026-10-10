import CoreGraphics

/// A colour stored as sRGB components so it can be saved with the settings.
struct RGBAColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: CGColor) {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB).flatMap {
            color.converted(to: $0, intent: .defaultIntent, options: nil)
        } ?? color
        let components = (srgb.components ?? []).map(Double.init)
        switch components.count {
        case 4...:
            self.init(red: components[0], green: components[1], blue: components[2], alpha: components[3])
        case 2:
            self.init(red: components[0], green: components[0], blue: components[0], alpha: components[1])
        default:
            self.init(red: 1, green: 1, blue: 1)
        }
    }

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
