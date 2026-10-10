@preconcurrency import AVFoundation
import CoreVideo
import Foundation

struct DeviceOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let frame: Locked<CVPixelBuffer?>
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "coops.wreckingball.camera-session")
    private let sampleQueue = DispatchQueue(label: "coops.wreckingball.camera-frames", qos: .userInteractive)

    init(frame: Locked<CVPixelBuffer?>) {
        self.frame = frame
    }

    static func devices() -> [DeviceOption] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        ).devices.map { DeviceOption(id: $0.uniqueID, name: $0.localizedName) }
    }

    func start(deviceID: String?) {
        sessionQueue.async { [self] in
            session.beginConfiguration()
            for input in session.inputs {
                session.removeInput(input)
            }
            if session.canSetSessionPreset(.hd1280x720) {
                session.sessionPreset = .hd1280x720
            }
            let device = deviceID.flatMap { AVCaptureDevice(uniqueID: $0) } ?? AVCaptureDevice.default(for: .video)
            if let device, let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.addInput(input)
            }
            if session.outputs.isEmpty, session.canAddOutput(output) {
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: sampleQueue)
                session.addOutput(output)
            }
            session.commitConfiguration()
            if !session.inputs.isEmpty, !session.isRunning {
                session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
            sampleQueue.async { self.frame.set(nil) }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = sampleBuffer.imageBuffer else { return }
        frame.set(buffer)
    }
}
