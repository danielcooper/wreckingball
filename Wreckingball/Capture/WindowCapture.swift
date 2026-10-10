import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit

/// Owns the single `SCStream` for the presented window. Switching windows swaps the
/// stream's content filter, so there is no gap while recording.
final class WindowCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private struct State {
        var targetBox = CGSize(width: 1920, height: 1080)
        var fps = 30
        /// Native pixel size of the window the stream is currently configured for.
        var configuredNative = CGSize.zero
        /// Native pixel size last reported by frame metadata.
        var reportedNative = CGSize.zero
        /// Increments on every switch; set back to nil once the new window delivers a frame.
        var switchGeneration = 0
        var awaitingFrame: Int?
    }

    private let frame: Locked<CVPixelBuffer?>
    private let state = Locked(State())
    private let chain = Locked<Task<Void, Never>?>(nil)
    private let sampleQueue = DispatchQueue(label: "coops.wreckingball.window-capture", qos: .userInteractive)

    // Only touched by operations queued on `chain`.
    private var stream: SCStream?
    private var filter: SCContentFilter?

    init(frame: Locked<CVPixelBuffer?>) {
        self.frame = frame
    }

    /// Presents `window`, or stops capturing when nil.
    func show(_ window: SCWindow?) {
        let boxed = Unchecked(window)
        enqueue { await self.apply(window: boxed.value) }
    }

    func updateTarget(box: CGSize, fps: Int) {
        let changed = state.withLock { state -> Bool in
            guard state.targetBox != box || state.fps != fps else { return false }
            state.targetBox = box
            state.fps = fps
            return true
        }
        if changed {
            enqueue { await self.reconfigure() }
        }
    }

    // MARK: Serialised operations

    private func enqueue(_ operation: @escaping @Sendable () async -> Void) {
        chain.withLock { tail in
            let previous = tail
            tail = Task {
                await previous?.value
                await operation()
            }
        }
    }

    private func apply(window: SCWindow?) async {
        guard let window else {
            await stop()
            return
        }
        let newFilter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(newFilter.pointPixelScale)
        let native = CGSize(width: newFilter.contentRect.width * scale, height: newFilter.contentRect.height * scale)
        state.withLock { state in
            state.configuredNative = native
            state.reportedNative = .zero
        }
        let configuration = makeConfiguration(native: native)

        do {
            if let stream {
                try await stream.updateContentFilter(newFilter)
                try await stream.updateConfiguration(configuration)
            } else {
                let created = SCStream(filter: newFilter, configuration: configuration, delegate: self)
                try created.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
                try await created.startCapture()
                stream = created
            }
            filter = newFilter
            clearIfNoFrameArrives()
        } catch {
            Log.capture.error("Window capture failed: \(error.localizedDescription)")
            await stop()
        }
    }

    /// The previous window's last frame stays up until the new window's first frame arrives, which
    /// keeps switches seamless. If the new window never delivers one, drop the stale frame.
    private func clearIfNoFrameArrives() {
        let generation = state.withLock { state -> Int in
            state.switchGeneration += 1
            state.awaitingFrame = state.switchGeneration
            return state.switchGeneration
        }
        Task {
            try? await Task.sleep(for: .seconds(1))
            let stillWaiting = self.state.withLock { $0.awaitingFrame == generation }
            if stillWaiting {
                Log.capture.warning("Presented window delivered no frames; showing background")
                self.frame.set(nil)
            }
        }
    }

    private func reconfigure() async {
        guard let stream else { return }
        let native = state.withLock { state -> CGSize in
            if state.reportedNative != .zero {
                state.configuredNative = state.reportedNative
            }
            return state.configuredNative
        }
        do {
            try await stream.updateConfiguration(makeConfiguration(native: native))
        } catch {
            Log.capture.error("Window capture reconfigure failed: \(error.localizedDescription)")
        }
    }

    private func stop() async {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        filter = nil
        frame.set(nil)
    }

    private func makeConfiguration(native: CGSize) -> SCStreamConfiguration {
        let (box, fps) = state.withLock { ($0.targetBox, $0.fps) }
        // Let ScreenCaptureKit do the downscale to the size the window occupies on the canvas.
        let scale = native.width > 0 && native.height > 0
            ? min(1, box.width / native.width, box.height / native.height)
            : 1
        let configuration = SCStreamConfiguration()
        configuration.width = max(2, Int((native.width * scale / 2).rounded()) * 2)
        configuration.height = max(2, Int((native.height * scale / 2).rounded()) * 2)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.scalesToFit = true
        configuration.showsCursor = true
        configuration.queueDepth = 5
        configuration.ignoreShadowsSingleWindow = true
        configuration.backgroundColor = .clear
        configuration.capturesAudio = false
        return configuration
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first,
              let rawStatus = info[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let buffer = sampleBuffer.imageBuffer
        else { return }

        frame.set(buffer)
        state.withLock { $0.awaitingFrame = nil }

        // Follow window resizes: work out the window's native pixel size from the frame metadata.
        guard let rectValue = info[.contentRect],
              let rect = CGRect(dictionaryRepresentation: rectValue as! CFDictionary),
              let contentScale = info[.contentScale] as? CGFloat, contentScale > 0,
              let scaleFactor = info[.scaleFactor] as? CGFloat
        else { return }
        let native = CGSize(
            width: rect.width / contentScale * scaleFactor,
            height: rect.height / contentScale * scaleFactor
        )
        let needsUpdate = state.withLock { state -> Bool in
            let previous = state.reportedNative
            guard abs(previous.width - native.width) > 2 || abs(previous.height - native.height) > 2 else { return false }
            state.reportedNative = native
            return abs(state.configuredNative.width - native.width) > 2 || abs(state.configuredNative.height - native.height) > 2
        }
        if needsUpdate {
            enqueue { await self.reconfigure() }
        }
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Log.capture.error("Window stream stopped: \(error.localizedDescription)")
        let stopped = Unchecked(stream)
        enqueue {
            guard self.stream === stopped.value else { return }
            self.stream = nil
            self.filter = nil
            self.frame.set(nil)
        }
    }
}
