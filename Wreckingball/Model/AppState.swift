import AppKit
import AVFoundation
import CoreImage
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppState {
    var settings: CanvasSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            engine.apply(settings)
            if settings.cameraVisible(presenting: isPresenting) != oldValue.cameraVisible(presenting: isPresenting)
                || settings.cameraDeviceID != oldValue.cameraDeviceID {
                updateCamera()
            }
            if settings.micDeviceID != oldValue.micDeviceID {
                updateMic()
            }
            if settings.resolution != oldValue.resolution {
                presentation.setAspect(settings.canvasSize)
            }
            keystrokeMonitor.mode = settings.keystrokeMode
            if settings.keystrokesEnabled != oldValue.keystrokesEnabled {
                keystrokeMonitor.setEnabled(settings.keystrokesEnabled)
            }
        }
    }

    var pins: [Pin] {
        didSet { Pin.save(pins) }
    }

    private(set) var selectedWindowID: CGWindowID?
    private(set) var isRecording = false {
        didSet { updateKeystrokeSample() }
    }
    /// The settings panel shown over the window list, if any.
    var inspector: Inspector? {
        didSet { updateKeystrokeSample() }
    }
    /// The keystroke panel is open: show a draggable sample pill on the canvas.
    var editingKeystrokes: Bool { inspector == .keystrokes }
    /// The canvas is mirrored in its own window, ready to be shared in a call. Recording and
    /// presenting are mutually exclusive, so the canvas only ever needs one camera setting.
    private(set) var isPresenting = false
    /// Whether the camera is on the canvas right now, which depends on the mode.
    var cameraVisible: Bool { settings.cameraVisible(presenting: isPresenting) }
    private(set) var isFinishing = false
    /// Recording is running but nothing is being written to the file.
    private(set) var isPaused = false
    private(set) var recordingStart: Date?
    @ObservationIgnored private var pausedTotal: TimeInterval = 0
    @ObservationIgnored private var pausedSince: Date?
    private(set) var lastRecording: URL?
    var errorMessage: String?

    private(set) var cameras: [DeviceOption] = []
    private(set) var mics: [DeviceOption] = []
    private(set) var cameraDenied = false
    private(set) var micDenied = false
    private(set) var micLevel: Float = 0
    /// Keystrokes are switched on but Input Monitoring access has not been granted.
    private(set) var keystrokeAccessMissing = false

    let catalog = WindowCatalog()
    @ObservationIgnored let engine = Engine()
    @ObservationIgnored private let presentation = PresentationWindow()
    @ObservationIgnored private var levelTimer: Timer?
    @ObservationIgnored private lazy var keystrokeMonitor: KeystrokeMonitor = {
        let monitor = KeystrokeMonitor(display: engine.keystrokes)
        monitor.mode = settings.keystrokeMode
        monitor.isExcluded = { Hotkeys.isOwnShortcut(keyCode: $0, modifiers: $1) }
        monitor.onAccessChange = { [weak self] missing in
            guard let self, missing != self.keystrokeAccessMissing else { return }
            self.keystrokeAccessMissing = missing
            if missing {
                self.errorMessage = "To show keystrokes, allow Wreckingball in System Settings → Privacy & Security → Input Monitoring. They'll appear as soon as access is granted (you may need to relaunch)."
            }
        }
        return monitor
    }()

    init() {
        settings = CanvasSettings.load()
        pins = Pin.load()
        engine.apply(settings)

        presentation.onClose = { [weak self] in self?.setPresenting(false) }
        catalog.onUpdate = { [weak self] in self?.catalogDidUpdate() }
        catalog.start()
        Hotkeys.register(self)
        if settings.keystrokesEnabled {
            keystrokeMonitor.setEnabled(true)
        }

        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.micLevel = self.engine.mic.level.get()
            }
        }

        Task {
            cameraDenied = !(await AVCaptureDevice.requestAccess(for: .video))
            micDenied = !(await AVCaptureDevice.requestAccess(for: .audio))
            refreshDevices()
            updateCamera()
            updateMic()
        }
    }

    /// Opens the panel, or closes it if it is already showing.
    func toggleInspector(_ panel: Inspector) {
        inspector = inspector == panel ? nil : panel
    }

    /// Shows or hides the window that mirrors the canvas for screen sharing.
    func togglePresentation() {
        if presentation.isOpen {
            presentation.close()
        } else {
            guard !isRecording, !isFinishing else { return }
            presentation.show(layer: engine.presentationLayer, aspect: settings.canvasSize)
        }
        setPresenting(presentation.isOpen)
    }

    /// The camera setting that applies changes with the mode, so the canvas and the capture
    /// session both need refreshing.
    private func setPresenting(_ presenting: Bool) {
        guard presenting != isPresenting else { return }
        isPresenting = presenting
        engine.setPresenting(presenting)
        updateCamera()
    }

    /// The sample pill is never shown while recording, so it can't end up in a video.
    private func updateKeystrokeSample() {
        engine.showKeystrokeSample.set(editingKeystrokes && !isRecording)
    }

    // MARK: Devices

    func refreshDevices() {
        cameras = CameraCapture.devices()
        mics = MicCapture.devices()
    }

    private func updateCamera() {
        if cameraVisible, !cameraDenied {
            engine.camera.start(deviceID: settings.cameraDeviceID)
        } else {
            engine.camera.stop()
        }
    }

    private func updateMic() {
        guard !micDenied else { return }
        engine.mic.start(deviceID: settings.micDeviceID)
    }

    // MARK: Window selection

    func select(_ window: WindowInfo?, activate: Bool = true) {
        selectedWindowID = window?.id
        engine.windowCapture.show(window?.window)
        if let window, activate, settings.activateOnSwitch {
            NSRunningApplication(processIdentifier: window.pid)?.activate()
        }
    }

    func isPinned(_ window: WindowInfo) -> Bool {
        pins.contains { $0.matches(window) }
    }

    func togglePin(_ window: WindowInfo) {
        if let index = pins.firstIndex(where: { $0.matches(window) }) {
            pins.remove(at: index)
        } else if pins.count < Pin.maxCount {
            pins.append(Pin(bundleID: window.bundleID, appName: window.appName, title: window.title))
        } else {
            errorMessage = "All \(Pin.maxCount) pin slots are in use. Unpin a window first."
        }
    }

    /// Windows that next/previous cycles through: pinned ones if any are open, otherwise everything on screen.
    private var cycleWindows: [WindowInfo] {
        var seen = Set<CGWindowID>()
        let pinned = pins
            .compactMap { $0.resolve(in: catalog.windows) }
            .filter { seen.insert($0.id).inserted }
        return pinned.isEmpty ? catalog.windows : pinned
    }

    private func cycle(by step: Int) {
        let windows = cycleWindows
        guard !windows.isEmpty else { return }
        guard let current = windows.firstIndex(where: { $0.id == selectedWindowID }) else {
            select(step > 0 ? windows.first : windows.last)
            return
        }
        select(windows[(current + step + windows.count) % windows.count])
    }

    private func catalogDidUpdate() {
        // The presented window was closed: fall back to the background.
        if let selectedWindowID, catalog.window(id: selectedWindowID) == nil, !catalog.permissionDenied {
            select(nil)
        }
    }

    // MARK: Commands

    func perform(_ command: Command) {
        switch command {
        case .toggleRecording:
            toggleRecording()
        case .startRecording:
            if !isRecording { toggleRecording() }
        case .stopRecording:
            if isRecording { toggleRecording() }
        case .togglePause:
            togglePause()
        case .pauseRecording:
            if !isPaused { togglePause() }
        case .resumeRecording:
            if isPaused { togglePause() }
        case .pin(let slot):
            guard pins.indices.contains(slot - 1),
                  let window = pins[slot - 1].resolve(in: catalog.windows)
            else { return }
            select(window)
        case .nextWindow:
            cycle(by: 1)
        case .previousWindow:
            cycle(by: -1)
        case .toggleCamera:
            // Toggles the setting for the mode you are in, so the shortcut always does something
            // you can see.
            if isPresenting {
                settings.cameraWhenPresenting.toggle()
            } else {
                settings.cameraWhenRecording.toggle()
            }
        case .toggleKeystrokes:
            settings.keystrokesEnabled.toggle()
        }
    }

    func handle(url: URL) {
        guard let command = Command(url: url) else {
            Log.app.error("Unrecognised URL: \(url.absoluteString)")
            return
        }
        perform(command)
    }

    // MARK: Recording

    var outputFolder: URL {
        if let path = settings.outputFolder {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Movies")
        return movies.appending(path: "Wreckingball", directoryHint: .isDirectory)
    }

    func toggleRecording() {
        guard !isFinishing else { return }
        if isRecording {
            stopRecording()
        } else {
            guard !isPresenting else {
                errorMessage = "Wreckingball can record or present, not both. Close the presentation window first."
                return
            }
            startRecording()
        }
    }

    /// Pauses or resumes writing. The preview and the window being presented carry on as normal.
    func togglePause() {
        guard isRecording else { return }
        if isPaused {
            pausedTotal += Date().timeIntervalSince(pausedSince ?? Date())
            pausedSince = nil
            isPaused = false
            engine.recorder.resume()
        } else {
            pausedSince = Date()
            isPaused = true
            engine.recorder.pause()
        }
    }

    /// How much video is in the file so far, which excludes time spent paused.
    func recordedSeconds(at now: Date) -> TimeInterval {
        guard let recordingStart else { return 0 }
        let paused = pausedTotal + (pausedSince.map { now.timeIntervalSince($0) } ?? 0)
        return max(0, now.timeIntervalSince(recordingStart) - paused)
    }

    private func startRecording() {
        do {
            let folder = outputFolder
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            let url = folder.appending(path: "Wreckingball \(formatter.string(from: Date())).mp4")
            try engine.recorder.start(
                url: url,
                settings: settings,
                audioFormat: micDenied ? nil : engine.mic.format.get()
            )
            isRecording = true
            isPaused = false
            pausedTotal = 0
            pausedSince = nil
            recordingStart = Date()
        } catch {
            errorMessage = "Could not start recording: \(error.localizedDescription)"
        }
    }

    private func stopRecording() {
        isRecording = false
        isPaused = false
        isFinishing = true
        recordingStart = nil
        pausedSince = nil
        Task {
            let url = await engine.recorder.stop()
            isFinishing = false
            if let url {
                lastRecording = url
            } else {
                errorMessage = "The recording could not be saved."
            }
        }
    }

    func revealLastRecording() {
        guard let lastRecording else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastRecording])
    }

    // MARK: Background

    func chooseBackground() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a background image"
        if panel.runModal() == .OK, let url = panel.url {
            setBackgroundImage(url)
        }
    }

    /// Uses the wallpaper of the screen Wreckingball's window is on.
    func useDesktopPicture() {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        guard let screen, let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            errorMessage = "Couldn't find the desktop picture."
            return
        }
        setBackgroundImage(url)
    }

    private func setBackgroundImage(_ url: URL) {
        guard CIImage(contentsOf: url) != nil else {
            errorMessage = "\(url.lastPathComponent) can't be used as a background. Moving or dynamic wallpapers aren't supported; try a still image."
            return
        }
        settings.background.kind = .image
        settings.background.imagePath = url.path
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = outputFolder
        if panel.runModal() == .OK, let url = panel.url {
            settings.outputFolder = url.path
        }
    }
}
