import CoreMedia
import CoreVideo
import Foundation
import QuartzCore

/// The frame pipeline: a fixed-rate clock composites the latest window and camera frames,
/// then hands the result to the preview layer and the recorder.
final class Engine: @unchecked Sendable {
    let previewLayer = Engine.makeOutputLayer()
    /// Shows the same frames as the preview in the presentation window, which is shared in a call.
    let presentationLayer = Engine.makeOutputLayer()
    let windowCapture: WindowCapture
    let camera: CameraCapture
    let mic = MicCapture()
    let recorder = Recorder()
    let keystrokes = Locked(KeystrokeDisplay())
    /// Show a sample pill so its position and style can be adjusted. Kept off while recording.
    let showKeystrokeSample = Locked(false)
    /// Where the keystroke pill was last drawn, normalised to the canvas with a top-left origin.
    let keystrokeRect = Locked<CGRect?>(nil)

    private let windowFrame = Locked<CVPixelBuffer?>(nil)
    private let cameraFrame = Locked<CVPixelBuffer?>(nil)
    private let settings = Locked(CanvasSettings())
    /// The presentation window is open, so the canvas follows the presenting camera setting.
    private let presenting = Locked(false)
    private let compositor = Compositor()
    private let renderQueue = DispatchQueue(label: "coops.wreckingball.render", qos: .userInteractive)

    // Main thread only.
    private var timer: DispatchSourceTimer?
    private var timerFPS = 0

    init() {
        windowCapture = WindowCapture(frame: windowFrame)
        camera = CameraCapture(frame: cameraFrame)
        let recorder = recorder
        mic.onSample.set { sample in recorder.appendAudio(sample) }
    }

    private static func makeOutputLayer() -> CALayer {
        let layer = CALayer()
        layer.contentsGravity = .resizeAspect
        layer.backgroundColor = CGColor(gray: 0, alpha: 1)
        return layer
    }

    /// Call on the main thread when the presentation window opens or closes.
    func setPresenting(_ value: Bool) {
        presenting.set(value)
    }

    /// Call on the main thread whenever settings change.
    func apply(_ newSettings: CanvasSettings) {
        settings.set(newSettings)
        windowCapture.updateTarget(box: newSettings.windowBox, fps: newSettings.fps)
        if newSettings.fps != timerFPS {
            startClock(fps: newSettings.fps)
        }
    }

    private func startClock(fps: Int) {
        timer?.cancel()
        timerFPS = fps
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: renderQueue)
        timer.schedule(deadline: .now(), repeating: 1.0 / Double(fps), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    /// The keystroke text and its opacity: fully visible for a moment after the last key, then
    /// fading. While the style is being edited, a sample stands in when nothing has been pressed.
    private func keystrokeOverlay(settings: CanvasSettings) -> (text: String, opacity: CGFloat)? {
        if settings.keystrokesEnabled {
            let state = keystrokes.get()
            let age = ProcessInfo.processInfo.systemUptime - state.updatedAt
            let hold = 1.6
            let fade = 0.4
            if !state.text.isEmpty, age < hold + fade {
                return (state.text, age <= hold ? 1 : CGFloat(1 - (age - hold) / fade))
            }
        }
        return showKeystrokeSample.get() ? (Self.keystrokeSample, 1) : nil
    }

    private static let keystrokeSample = "⌘⇧K"

    private func tick() {
        let current = settings.get()
        guard let buffer = compositor.render(
            settings: current,
            window: windowFrame.get(),
            camera: current.cameraVisible(presenting: presenting.get()) ? cameraFrame.get() : nil,
            keystrokes: keystrokeOverlay(settings: current)
        ) else { return }

        let size = current.canvasSize
        keystrokeRect.set(compositor.keystrokeRect.map { rect in
            CGRect(
                x: rect.minX / size.width,
                y: 1 - rect.maxY / size.height,
                width: rect.width / size.width,
                height: rect.height / size.height
            )
        })

        recorder.appendVideo(buffer, at: CMClockGetTime(CMClockGetHostTimeClock()))

        let frame = Unchecked((layers: [previewLayer, presentationLayer], buffer: buffer))
        DispatchQueue.main.async {
            guard let surface = CVPixelBufferGetIOSurface(frame.value.buffer)?.takeUnretainedValue() else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for layer in frame.value.layers {
                layer.contents = surface
            }
            CATransaction.commit()
        }
    }
}
