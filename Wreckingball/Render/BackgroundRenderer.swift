import CoreGraphics
import Foundation

/// Draws gradient backgrounds with Core Graphics. Pure drawing, so it is used both by the
/// compositor and for the preset swatches in the panel.
enum BackgroundRenderer {
    static func gradient(_ background: BackgroundSettings, size: CGSize) -> CGImage? {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard size.width >= 1, size.height >= 1,
              let context = CGContext(
                  data: nil,
                  width: Int(size.width),
                  height: Int(size.height),
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        let colors = background.colors.isEmpty ? BackgroundPreset.twilight.colors : background.colors
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        switch background.gradientKind {
        case .linear:
            guard let gradient = makeGradient(colors.map(\.cgColor), space: space) else { return nil }
            let radians = background.angle * .pi / 180
            let direction = CGPoint(x: cos(radians), y: sin(radians))
            // Half the gradient's length, so it spans the canvas corner to corner at any angle.
            let half = (abs(size.width * direction.x) + abs(size.height * direction.y)) / 2
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: center.x - direction.x * half, y: center.y - direction.y * half),
                end: CGPoint(x: center.x + direction.x * half, y: center.y + direction.y * half),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )

        case .radial:
            guard let gradient = makeGradient(colors.map(\.cgColor), space: space) else { return nil }
            let radius = hypot(size.width, size.height) / 2
            context.drawRadialGradient(
                gradient,
                startCenter: center, startRadius: 0,
                endCenter: center, endRadius: radius,
                options: [.drawsAfterEndLocation]
            )

        case .aurora:
            // The first colour fills the canvas; the others glow from fixed spots across it.
            context.setFillColor(colors[0].cgColor)
            context.fill(CGRect(origin: .zero, size: size))
            let accents = colors.count > 1 ? Array(colors.dropFirst()) : colors
            let spots: [(x: CGFloat, y: CGFloat, radius: CGFloat)] = [
                (0.16, 0.80, 0.40), (0.84, 0.74, 0.36), (0.58, 0.22, 0.42), (0.04, 0.08, 0.26), (0.96, 0.12, 0.24),
            ]
            let scale = max(size.width, size.height)
            for (index, spot) in spots.enumerated() {
                var accent = accents[index % accents.count]
                accent.alpha = 0.85
                var clear = accent
                clear.alpha = 0
                guard let glow = makeGradient([accent.cgColor, clear.cgColor], space: space) else { continue }
                let point = CGPoint(x: spot.x * size.width, y: spot.y * size.height)
                context.drawRadialGradient(
                    glow,
                    startCenter: point, startRadius: 0,
                    endCenter: point, endRadius: spot.radius * scale,
                    options: []
                )
            }
        }
        return context.makeImage()
    }

    private static func makeGradient(_ colors: [CGColor], space: CGColorSpace) -> CGGradient? {
        let locations = colors.count > 1
            ? (0..<colors.count).map { CGFloat($0) / CGFloat(colors.count - 1) }
            : [0]
        return CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)
    }
}
