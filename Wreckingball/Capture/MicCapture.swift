@preconcurrency import AVFoundation
import Foundation

final class MicCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// Receives every audio sample buffer on the capture queue.
    let onSample = Locked<(@Sendable (CMSampleBuffer) -> Void)?>(nil)
    /// Input level from 0 to 1.
    let level = Locked<Float>(0)
    /// Format of the most recent audio, used to configure the recorder.
    let format = Locked<CMFormatDescription?>(nil)

    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let sessionQueue = DispatchQueue(label: "coops.wreckingball.mic-session")
    private let sampleQueue = DispatchQueue(label: "coops.wreckingball.mic-samples", qos: .userInitiated)

    static func devices() -> [DeviceOption] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices.map { DeviceOption(id: $0.uniqueID, name: $0.localizedName) }
    }

    func start(deviceID: String?) {
        sessionQueue.async { [self] in
            session.beginConfiguration()
            for input in session.inputs {
                session.removeInput(input)
            }
            format.set(nil)
            let device = deviceID.flatMap { AVCaptureDevice(uniqueID: $0) } ?? AVCaptureDevice.default(for: .audio)
            if let device, let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.addInput(input)
            }
            if session.outputs.isEmpty, session.canAddOutput(output) {
                output.setSampleBufferDelegate(self, queue: sampleQueue)
                session.addOutput(output)
            }
            session.commitConfiguration()
            if !session.inputs.isEmpty, !session.isRunning {
                session.startRunning()
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if let description = sampleBuffer.formatDescription {
            format.set(description)
        }
        if let channel = connection.audioChannels.first {
            // Map -50 dB ... 0 dB onto 0 ... 1.
            level.set(max(0, min(1, (channel.averagePowerLevel + 50) / 50)))
        }
        onSample.get()?(sampleBuffer)
    }
}
