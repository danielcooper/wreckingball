import CoreGraphics
import Foundation

enum CameraShape: String, Codable, CaseIterable, Identifiable, Sendable {
    case circle, squircle, roundedSquare, wide, hexagon

    var id: String { rawValue }

    var label: String {
        switch self {
        case .circle: "Circle"
        case .squircle: "Squircle"
        case .roundedSquare: "Rounded square"
        case .wide: "Wide"
        case .hexagon: "Hexagon"
        }
    }

    /// Width divided by height of the shape's bounding box.
    var aspect: CGFloat {
        self == .wide ? 16.0 / 10.0 : 1
    }

    func path(in rect: CGRect) -> CGPath {
        let side = min(rect.width, rect.height)
        switch self {
        case .circle:
            return CGPath(ellipseIn: rect, transform: nil)
        case .roundedSquare:
            return CGPath(roundedRect: rect, cornerWidth: side * 0.2, cornerHeight: side * 0.2, transform: nil)
        case .wide:
            return CGPath(roundedRect: rect, cornerWidth: side * 0.16, cornerHeight: side * 0.16, transform: nil)
        case .squircle:
            return Self.superellipse(in: rect, exponent: 4.5)
        case .hexagon:
            return Self.roundedPolygon(in: rect, sides: 6, cornerRadius: side * 0.08)
        }
    }

    private static func superellipse(in rect: CGRect, exponent: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let a = rect.width / 2
        let b = rect.height / 2
        let steps = 180
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
            let cosT = cos(t)
            let sinT = sin(t)
            let x = rect.midX + a * copysign(pow(abs(cosT), 2 / exponent), cosT)
            let y = rect.midY + b * copysign(pow(abs(sinT), 2 / exponent), sinT)
            if step == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }

    private static func roundedPolygon(in rect: CGRect, sides: Int, cornerRadius: CGFloat) -> CGPath {
        let radius = min(rect.width, rect.height) / 2
        let vertices = (0..<sides).map { index -> CGPoint in
            let angle = CGFloat(index) / CGFloat(sides) * 2 * .pi + .pi / 2
            return CGPoint(x: rect.midX + radius * cos(angle), y: rect.midY + radius * sin(angle))
        }
        let path = CGMutablePath()
        let last = vertices[sides - 1]
        let first = vertices[0]
        path.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
        for index in 0..<sides {
            path.addArc(tangent1End: vertices[index], tangent2End: vertices[(index + 1) % sides], radius: cornerRadius)
        }
        path.closeSubpath()
        return path
    }
}
