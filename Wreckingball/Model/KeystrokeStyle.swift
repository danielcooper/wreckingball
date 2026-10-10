import AppKit
import CoreText

/// How the keystroke pill looks.
struct KeystrokeStyle: Codable, Equatable, Sendable {
    /// "system", "rounded", "monospaced", "serif", or an installed font family name.
    var font = "system"
    /// Point size on a 1080p canvas.
    var fontSize = 38.0
    var bold = true
    var textColor = RGBAColor(red: 1, green: 1, blue: 1)
    var backgroundColor = RGBAColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 0.78)
    /// Border width on a 1080p canvas; 0 for none.
    var outlineWidth = 1.5
    var outlineColor = RGBAColor(red: 1, green: 1, blue: 1, alpha: 0.16)

    static let systemDesigns: [(tag: String, label: String)] = [
        ("system", "System"),
        ("rounded", "System Rounded"),
        ("monospaced", "System Mono"),
        ("serif", "System Serif"),
    ]

    func makeFont(size: CGFloat) -> CTFont {
        let weight: NSFont.Weight = bold ? .bold : .medium
        let design: NSFontDescriptor.SystemDesign?
        switch font {
        case "system": design = .default
        case "rounded": design = .rounded
        case "monospaced": design = .monospaced
        case "serif": design = .serif
        default: design = nil
        }

        if let design {
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            guard let descriptor = base.fontDescriptor.withDesign(design),
                  let designed = NSFont(descriptor: descriptor, size: size)
            else { return base as CTFont }
            return designed as CTFont
        }

        var attributes: [CFString: Any] = [kCTFontFamilyNameAttribute: font]
        if bold {
            attributes[kCTFontTraitsAttribute] = [kCTFontSymbolicTrait: CTFontSymbolicTraits.traitBold.rawValue]
        }
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }
}

extension KeystrokeStyle {
    init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        font = value(.font, font)
        fontSize = value(.fontSize, fontSize)
        bold = value(.bold, bold)
        textColor = value(.textColor, textColor)
        backgroundColor = value(.backgroundColor, backgroundColor)
        outlineWidth = value(.outlineWidth, outlineWidth)
        outlineColor = value(.outlineColor, outlineColor)
    }
}
