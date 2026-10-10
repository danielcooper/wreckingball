import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Draws the Wreckingball app icon in a 1024-point design space at any pixel size.

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [r, g, b, a])!
}

func draw(in ctx: CGContext, pixels: Int) {
    let scale = CGFloat(pixels) / 1024
    let small = pixels <= 32
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: scale, y: -scale) // top-left origin, 1024 units

    // Background tile, following the macOS icon grid (824pt body inside 1024).
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: color(0, 0, 0, 0.35))
    ctx.addPath(tilePath)
    ctx.setFillColor(color(0.12, 0.10, 0.25))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let background = CGGradient(colorsSpace: sRGB, colors: [
        color(0.40, 0.25, 0.56),
        color(0.20, 0.15, 0.38),
        color(0.07, 0.08, 0.18),
    ] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 160, y: 100), end: CGPoint(x: 860, y: 924), options: [])

    // Soft glow behind the ball.
    let glow = CGGradient(colorsSpace: sRGB, colors: [color(0.85, 0.80, 1, 0.22), color(0.85, 0.80, 1, 0)] as CFArray, locations: [0, 1])!
    let ballCenter = CGPoint(x: 572, y: 590)
    ctx.drawRadialGradient(glow, startCenter: ballCenter, startRadius: 0, endCenter: ballCenter, endRadius: 420, options: [])

    // Swing: pivot above the tile, chain down to the ball.
    let pivot = CGPoint(x: 470, y: -40)
    let ballRadius: CGFloat = 262
    let dx = ballCenter.x - pivot.x
    let dy = ballCenter.y - pivot.y
    let length = (dx * dx + dy * dy).squareRoot()
    let unit = CGPoint(x: dx / length, y: dy / length)
    let angle = atan2(dy, dx)

    // Motion arcs trailing the ball, centred on the pivot.
    ctx.setLineCap(.round)
    let arcs: [(radius: CGFloat, width: CGFloat, alpha: CGFloat, sweep: CGFloat)] = small
        ? [(length + 30, 40, 0.35, 0.36)]
        : [(length + 150, 18, 0.28, 0.30), (length + 30, 26, 0.40, 0.40), (length - 110, 18, 0.24, 0.30)]
    for arc in arcs {
        ctx.setStrokeColor(color(1, 1, 1, arc.alpha))
        ctx.setLineWidth(arc.width)
        ctx.addArc(center: pivot, radius: arc.radius, startAngle: angle + 0.42, endAngle: angle + 0.42 + arc.sweep, clockwise: false)
        ctx.strokePath()
    }

    // Chain.
    // Runs under the lug so the last link is tucked in.
    let chainLength = length - ballRadius + 4
    let chainEnd = CGPoint(x: pivot.x + unit.x * chainLength, y: pivot.y + unit.y * chainLength)
    let steel = color(0.80, 0.82, 0.88)
    if small {
        ctx.setStrokeColor(steel)
        ctx.setLineWidth(120)
        ctx.move(to: pivot)
        ctx.addLine(to: chainEnd)
        ctx.strokePath()
    } else {
        let pitch: CGFloat = 78
        var distance: CGFloat = 10
        var index = 0
        while distance < chainLength {
            let center = CGPoint(x: pivot.x + unit.x * distance, y: pivot.y + unit.y * distance)
            ctx.saveGState()
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: angle)
            if index.isMultiple(of: 2) {
                // Link seen face-on: an elongated ring.
                ctx.setStrokeColor(steel)
                ctx.setLineWidth(20)
                ctx.addPath(CGPath(roundedRect: CGRect(x: -54, y: -29, width: 108, height: 58), cornerWidth: 29, cornerHeight: 29, transform: nil))
                ctx.strokePath()
            } else {
                // Link seen edge-on: a solid bar.
                ctx.setFillColor(color(0.62, 0.64, 0.72))
                ctx.addPath(CGPath(roundedRect: CGRect(x: -54, y: -11, width: 108, height: 22), cornerWidth: 11, cornerHeight: 11, transform: nil))
                ctx.fillPath()
            }
            ctx.restoreGState()
            distance += pitch
            index += 1
        }
    }

    // The ball: heavy gunmetal steel.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 34), blur: 56, color: color(0, 0, 0, 0.45))
    ctx.addEllipse(in: CGRect(x: ballCenter.x - ballRadius, y: ballCenter.y - ballRadius, width: ballRadius * 2, height: ballRadius * 2))
    ctx.setFillColor(color(0.18, 0.19, 0.24))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: ballCenter.x - ballRadius, y: ballCenter.y - ballRadius, width: ballRadius * 2, height: ballRadius * 2))
    ctx.clip()
    let sphere = CGGradient(colorsSpace: sRGB, colors: [
        color(0.66, 0.69, 0.78),
        color(0.36, 0.38, 0.46),
        color(0.17, 0.18, 0.23),
        color(0.07, 0.07, 0.10),
    ] as CFArray, locations: [0, 0.35, 0.78, 1])!
    let light = CGPoint(x: ballCenter.x - 95, y: ballCenter.y - 110)
    ctx.drawRadialGradient(sphere, startCenter: light, startRadius: 0, endCenter: ballCenter, endRadius: ballRadius, options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    // Rim light on the shadow side so the dark ball separates from the background.
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: ballCenter.x - ballRadius, y: ballCenter.y - ballRadius, width: ballRadius * 2, height: ballRadius * 2))
    ctx.setStrokeColor(color(0.80, 0.74, 1, 0.35))
    ctx.setLineWidth(small ? 24 : 10)
    ctx.strokePath()
    ctx.restoreGState()

    // Specular highlight.
    if !small {
        let shine = CGGradient(colorsSpace: sRGB, colors: [color(1, 1, 1, 0.55), color(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
        ctx.saveGState()
        ctx.translateBy(x: ballCenter.x - 104, y: ballCenter.y - 128)
        ctx.rotate(by: -0.5)
        ctx.scaleBy(x: 1.6, y: 1)
        ctx.drawRadialGradient(shine, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 68, options: [])
        ctx.restoreGState()
    }

    // Lug where the chain meets the ball, sitting on top of it.
    ctx.saveGState()
    ctx.translateBy(x: ballCenter.x - unit.x * (ballRadius - 4), y: ballCenter.y - unit.y * (ballRadius - 4))
    ctx.rotate(by: angle + .pi / 2)
    let lugRect = CGRect(x: -70, y: -46, width: 140, height: 76)
    ctx.addPath(CGPath(roundedRect: lugRect, cornerWidth: 20, cornerHeight: 20, transform: nil))
    ctx.clip()
    let lugGradient = CGGradient(colorsSpace: sRGB, colors: [color(0.86, 0.88, 0.93), color(0.50, 0.52, 0.60)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(lugGradient, start: CGPoint(x: -70, y: 0), end: CGPoint(x: 70, y: 0), options: [])
    ctx.restoreGState()

    // Subtle top highlight on the tile.
    let sheen = CGGradient(colorsSpace: sRGB, colors: [color(1, 1, 1, 0.10), color(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 420), options: [])
    ctx.restoreGState()
}

func render(pixels: Int, to url: URL) {
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.interpolationQuality = .high
    draw(in: ctx, pixels: pixels)
    let image = ctx.makeImage()!
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    render(pixels: pixels, to: output.appendingPathComponent("icon_\(pixels).png"))
}
print("done")
