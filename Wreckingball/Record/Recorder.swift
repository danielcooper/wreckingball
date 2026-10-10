@preconcurrency import AVFoundation
import CoreVideo
import Foundation

/// Writes composited frames and microphone audio to an `.mp4`.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var sessionStart: CMTime?
    private var droppedFrames = 0

    func start(url: URL, settings: CanvasSettings, audioFormat: CMFormatDescription?) throws {
        let size = settings.canvasSize
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        var bitrate = size.width * size.height * 4.8 * (settings.fps > 30 ? 1.5 : 1)
        var compression: [String: Any] = [
            AVVideoExpectedSourceFrameRateKey: settings.fps,
            AVVideoMaxKeyFrameIntervalKey: settings.fps * 2,
        ]
        let codec: AVVideoCodecType
        switch settings.codec {
        case .h264:
            codec = .h264
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        case .hevc:
            codec = .hevc
            bitrate *= 0.65
        }
        compression[AVVideoAverageBitRateKey] = Int(bitrate)

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: compression,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        videoInput.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(videoInput) else { throw RecorderError.cannotConfigure }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if let audioFormat, let description = audioFormat.audioStreamBasicDescription {
            let channels = max(1, min(2, Int(description.mChannelsPerFrame)))
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: description.mSampleRate > 0 ? description.mSampleRate : 48000,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: channels == 1 ? 96_000 : 160_000,
            ], sourceFormatHint: audioFormat)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        guard writer.startWriting() else { throw writer.error ?? RecorderError.cannotConfigure }

        lock.lock()
        self.writer = writer
        self.videoInput = videoInput
        self.audioInput = audioInput
        self.adaptor = adaptor
        sessionStart = nil
        droppedFrames = 0
        lock.unlock()
    }

    func appendVideo(_ buffer: CVPixelBuffer, at time: CMTime) {
        lock.lock()
        defer { lock.unlock() }
        guard let writer, let videoInput, let adaptor, writer.status == .writing else { return }
        if sessionStart == nil {
            writer.startSession(atSourceTime: time)
            sessionStart = time
        }
        guard videoInput.isReadyForMoreMediaData else {
            droppedFrames += 1
            return
        }
        if !adaptor.append(buffer, withPresentationTime: time) {
            Log.recorder.error("Video append failed: \(writer.error?.localizedDescription ?? "unknown")")
        }
    }

    func appendAudio(_ sample: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let writer, let audioInput, let sessionStart, writer.status == .writing,
              sample.presentationTimeStamp >= sessionStart,
              audioInput.isReadyForMoreMediaData
        else { return }
        audioInput.append(sample)
    }

    /// Finishes the file and returns its URL, or nil if nothing was written.
    func stop() async -> URL? {
        let (writer, started, dropped) = detach()
        guard let writer else { return nil }
        guard started, writer.status == .writing else {
            writer.cancelWriting()
            return nil
        }
        if dropped > 0 {
            Log.recorder.warning("Dropped \(dropped) frames while recording")
        }
        let boxed = Unchecked(writer)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            boxed.value.finishWriting { continuation.resume() }
        }
        guard boxed.value.status == .completed else {
            Log.recorder.error("Recording failed: \(boxed.value.error?.localizedDescription ?? "unknown")")
            return nil
        }
        return boxed.value.outputURL
    }

    /// Ends both inputs and takes the writer out of service so no further samples are appended.
    private func detach() -> (writer: AVAssetWriter?, started: Bool, dropped: Int) {
        lock.lock()
        defer { lock.unlock() }
        let result = (writer, sessionStart != nil, droppedFrames)
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        writer = nil
        videoInput = nil
        audioInput = nil
        adaptor = nil
        sessionStart = nil
        return result
    }
}

enum RecorderError: LocalizedError {
    case cannotConfigure

    var errorDescription: String? {
        "The recording could not be started with these settings."
    }
}
