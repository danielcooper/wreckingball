import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
import CoreVideo
import Foundation
import Metal

/// Draws background, presented window and camera into a canvas-sized pixel buffer.
/// Used from the render queue only.
final class Compositor {
    private let context: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.itur_709) ?? CGColorSpaceCreateDeviceRGB()

    private var pool: CVPixelBufferPool?
    private var poolSize = CGSize.zero

    private var backgroundKey = ""
    private var background: CIImage?

    private var maskKey = ""
    private var cameraMask: CIImage?
    private var cameraShadow: CIImage?

    private var pillKey = ""
    private var pill: CIImage?

    /// Where the keystroke pill was drawn in the last frame, in canvas pixels (bottom-left origin).
    private(set) var keystrokeRect: CGRect?

    init() {
        let options: [CIContextOption: Any] = [.cacheIntermediates: false]
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: options)
        } else {
            context = CIContext(options: options)
        }
    }

    func render(
        settings: CanvasSettings,
        window: CVPixelBuffer?,
        camera: CVPixelBuffer?,
        keystrokes: (text: String, opacity: CGFloat)?
    ) -> CVPixelBuffer? {
        let size = settings.canvasSize
        let canvas = CGRect(origin: .zero, size: size)
        let unit = size.height / 1080
        guard let output = makeBuffer(size: size) else { return nil }

        var image = backgroundImage(settings.background, canvas: canvas, unit: unit)

        if let window {
            image = draw(window: CIImage(cvPixelBuffer: window), over: image, canvas: canvas, unit: unit, settings: settings)
        }
        if let camera {
            image = draw(camera: CIImage(cvPixelBuffer: camera), over: image, canvas: canvas, unit: unit, settings: settings)
        }
        keystrokeRect = nil
        if let keystrokes {
            image = draw(keystrokes: keystrokes.text, opacity: keystrokes.opacity, over: image, canvas: canvas, unit: unit, settings: settings)
        }

        context.render(image.cropped(to: canvas), to: output, bounds: canvas, colorSpace: colorSpace)
        return output
    }

    // MARK: Layers

    private func draw(window: CIImage, over base: CIImage, canvas: CGRect, unit: CGFloat, settings: CanvasSettings) -> CIImage {
        let source = window.extent
        guard source.width > 0, source.height > 0 else { return base }
        let box = settings.windowBox
        let scale = min(box.width / source.width, box.height / source.height)
        let width = (source.width * scale).rounded()
        let height = (source.height * scale).rounded()
        let rect = CGRect(
            x: ((canvas.width - width) / 2).rounded(),
            y: ((canvas.height - height) / 2).rounded(),
            width: width,
            height: height
        )

        let placed = window
            .transformed(by: CGAffineTransform(translationX: -source.minX, y: -source.minY))
            .transformed(by: CGAffineTransform(scaleX: width / source.width, y: height / source.height))
            .transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))

        let radius = min(settings.windowCornerRadius * unit, min(width, height) / 2)
        var result = base

        if settings.windowShadow {
            let shadow = roundedRect(rect, radius: radius, color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.5))
                .applyingGaussianBlur(sigma: 22 * unit)
                .transformed(by: CGAffineTransform(translationX: 0, y: -10 * unit))
            result = shadow.composited(over: result)
        }

        let mask = roundedRect(rect, radius: radius, color: .white)
        let clipped = placed.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: mask,
        ])
        return clipped.composited(over: result)
    }

    private func draw(camera: CIImage, over base: CIImage, canvas: CGRect, unit: CGFloat, settings: CanvasSettings) -> CIImage {
        let shape = settings.cameraShape
        let height = (settings.cameraSize * canvas.height).rounded()
        let width = (height * shape.aspect).rounded()
        guard width > 1, height > 1, camera.extent.width > 0, camera.extent.height > 0 else { return base }

        var image = camera
        if settings.cameraMirrored {
            image = image.transformed(by: CGAffineTransform(scaleX: -1, y: 1))
        }

        // Centre-crop the camera to the shape's aspect ratio.
        let extent = image.extent
        var crop = extent
        if extent.width / extent.height > shape.aspect {
            crop.size.width = extent.height * shape.aspect
            crop.origin.x = extent.midX - crop.width / 2
        } else {
            crop.size.height = extent.width / shape.aspect
            crop.origin.y = extent.midY - crop.height / 2
        }

        let origin = CGPoint(
            x: (settings.cameraCenter.x * canvas.width - width / 2).rounded(),
            y: ((1 - settings.cameraCenter.y) * canvas.height - height / 2).rounded()
        )
        let move = CGAffineTransform(translationX: origin.x, y: origin.y)

        let placed = image
            .cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            .transformed(by: CGAffineTransform(scaleX: width / crop.width, y: height / crop.height))
            .transformed(by: move)

        prepareMask(shape: shape, size: CGSize(width: width, height: height), unit: unit)
        guard let cameraMask, let cameraShadow else { return base }

        let clipped = placed.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: cameraMask.transformed(by: move),
        ])
        let shadow = cameraShadow.transformed(by: move.translatedBy(x: 0, y: -6 * unit))
        return clipped.composited(over: shadow.composited(over: base))
    }

    private func draw(keystrokes text: String, opacity: CGFloat, over base: CIImage, canvas: CGRect, unit: CGFloat, settings: CanvasSettings) -> CIImage {
        guard let pill = keystrokePill(text: text, unit: unit, style: settings.keystrokeStyle) else {
            Log.keys.error("Could not draw the keystroke overlay")
            return base
        }
        let size = pill.extent.size
        // Keep the whole pill on the canvas wherever its centre was dragged.
        let center = CGPoint(
            x: min(max(settings.keystrokeCenter.x * canvas.width, size.width / 2), canvas.width - size.width / 2),
            y: min(max((1 - settings.keystrokeCenter.y) * canvas.height, size.height / 2), canvas.height - size.height / 2)
        )
        let origin = CGPoint(x: (center.x - size.width / 2).rounded(), y: (center.y - size.height / 2).rounded())
        keystrokeRect = CGRect(origin: origin, size: size)

        var placed = pill.transformed(by: CGAffineTransform(translationX: origin.x, y: origin.y))
        if opacity < 1 {
            placed = placed.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity),
            ])
        }
        return placed.composited(over: base)
    }

    /// The keystroke pill, rasterised once per distinct text and style.
    private func keystrokePill(text: String, unit: CGFloat, style: KeystrokeStyle) -> CIImage? {
        let key = "\(text)|\(unit)|\(style)"
        if key == pillKey { return pill }
        pillKey = key
        pill = nil

        let fontSize = style.fontSize * unit
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): style.makeFont(size: fontSize),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): style.textColor.cgColor,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        let outline = style.outlineWidth * unit
        let padding = CGSize(width: fontSize * 0.68 + outline, height: fontSize * 0.42 + outline)
        let size = CGSize(
            width: (textWidth + padding.width * 2).rounded(.up),
            height: (ascent + descent + padding.height * 2).rounded(.up)
        )

        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let bounds = CGRect(origin: .zero, size: size)
        let radius = min(size.height / 2, fontSize * 0.47)
        context.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.setFillColor(style.backgroundColor.cgColor)
        context.fillPath()
        if outline > 0 {
            let inset = bounds.insetBy(dx: outline / 2, dy: outline / 2)
            let innerRadius = max(0, radius - outline / 2)
            context.addPath(CGPath(roundedRect: inset, cornerWidth: innerRadius, cornerHeight: innerRadius, transform: nil))
            context.setStrokeColor(style.outlineColor.cgColor)
            context.setLineWidth(outline)
            context.strokePath()
        }
        context.textPosition = CGPoint(x: padding.width, y: padding.height + descent)
        CTLineDraw(line, context)

        guard let image = context.makeImage() else { return nil }
        pill = CIImage(cgImage: image)
        return pill
    }

    private func roundedRect(_ rect: CGRect, radius: CGFloat, color: CIColor) -> CIImage {
        let filter = CIFilter.roundedRectangleGenerator()
        filter.extent = rect
        filter.radius = Float(radius)
        filter.color = color
        return filter.outputImage ?? CIImage(color: color).cropped(to: rect)
    }

    // MARK: Cached resources

    private func backgroundImage(_ settings: BackgroundSettings, canvas: CGRect, unit: CGFloat) -> CIImage {
        let key = "\(settings)|\(Int(canvas.width))x\(Int(canvas.height))"
        if key == backgroundKey, let background { return background }
        backgroundKey = key

        var image: CIImage
        switch settings.kind {
        case .solid:
            image = CIImage(color: CIColor(cgColor: settings.solidColor.cgColor)).cropped(to: canvas)
        case .gradient:
            image = gradientImage(settings, canvas: canvas)
        case .image:
            if let photo = photoImage(settings, canvas: canvas, unit: unit) {
                image = photo
            } else {
                Log.app.error("Background image could not be loaded; using the default gradient")
                image = gradientImage(BackgroundSettings(), canvas: canvas)
            }
        }

        if settings.vignette > 0 {
            image = image.applyingFilter("CIVignetteEffect", parameters: [
                kCIInputCenterKey: CIVector(x: canvas.midX, y: canvas.midY),
                kCIInputRadiusKey: hypot(canvas.width, canvas.height) * (0.62 - 0.22 * settings.vignette),
                kCIInputIntensityKey: settings.vignette,
                "inputFalloff": 0.6,
            ]).cropped(to: canvas)
        }

        if settings.grain > 0 {
            // Monochrome noise from the green channel, blended softly over the background.
            let channel = CIVector(x: 0, y: 1, z: 0, w: 0)
            let noise = CIFilter.randomGenerator().outputImage?
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": channel,
                    "inputGVector": channel,
                    "inputBVector": channel,
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0.45 * settings.grain),
                ])
                .cropped(to: canvas)
            if let noise {
                image = noise.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: image])
                    .cropped(to: canvas)
            }
        }

        // Flatten once so the per-frame cost is a single texture draw.
        if let flattened = context.createCGImage(image, from: canvas) {
            image = CIImage(cgImage: flattened)
        }
        background = image
        return image
    }

    private func gradientImage(_ settings: BackgroundSettings, canvas: CGRect) -> CIImage {
        guard let gradient = BackgroundRenderer.gradient(settings, size: canvas.size) else {
            return CIImage(color: .black).cropped(to: canvas)
        }
        return CIImage(cgImage: gradient)
    }

    /// The chosen image scaled to fill the canvas, then blurred and dimmed.
    private func photoImage(_ settings: BackgroundSettings, canvas: CGRect, unit: CGFloat) -> CIImage? {
        guard let path = settings.imagePath,
              let loaded = CIImage(contentsOf: URL(fileURLWithPath: path), options: [.applyOrientationProperty: true]),
              loaded.extent.width > 0, loaded.extent.height > 0
        else { return nil }

        let extent = loaded.extent
        let scale = max(canvas.width / extent.width, canvas.height / extent.height)
        let scaled = loaded
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0])
        let offset = CGAffineTransform(
            translationX: (canvas.width - scaled.extent.width) / 2 - scaled.extent.minX,
            y: (canvas.height - scaled.extent.height) / 2 - scaled.extent.minY
        )
        var image = scaled.transformed(by: offset).cropped(to: canvas)

        if settings.imageBlur > 0 {
            image = image.clampedToExtent()
                .applyingGaussianBlur(sigma: settings.imageBlur * unit)
                .cropped(to: canvas)
        }
        if settings.imageDim > 0 {
            image = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: settings.imageDim))
                .cropped(to: canvas)
                .composited(over: image)
        }
        return image
    }

    private func prepareMask(shape: CameraShape, size: CGSize, unit: CGFloat) {
        let key = "\(shape.rawValue)|\(Int(size.width))x\(Int(size.height))"
        guard key != maskKey else { return }
        maskKey = key
        cameraMask = nil
        cameraShadow = nil

        guard let bitmap = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        bitmap.addPath(shape.path(in: CGRect(origin: .zero, size: size)))
        bitmap.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        bitmap.fillPath()
        guard let rendered = bitmap.makeImage() else { return }

        let mask = CIImage(cgImage: rendered)
        let zero = CIVector(x: 0, y: 0, z: 0, w: 0)
        let shadow = mask
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": zero,
                "inputGVector": zero,
                "inputBVector": zero,
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.45),
            ])
            .applyingGaussianBlur(sigma: 14 * unit)
        cameraMask = mask
        // Flatten the blurred shadow so it is not recomputed every frame.
        let shadowExtent = shadow.extent.integral
        if let flattened = context.createCGImage(shadow, from: shadowExtent) {
            cameraShadow = CIImage(cgImage: flattened)
                .transformed(by: CGAffineTransform(translationX: shadowExtent.minX, y: shadowExtent.minY))
        } else {
            cameraShadow = shadow
        }
    }

    private func makeBuffer(size: CGSize) -> CVPixelBuffer? {
        if pool == nil || poolSize != size {
            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: Int(size.width),
                kCVPixelBufferHeightKey: Int(size.height),
                kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any](),
                kCVPixelBufferMetalCompatibilityKey: true,
            ]
            var created: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &created)
            pool = created
            poolSize = size
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return nil }
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        return buffer
    }
}
