import SwiftUI

struct ControlBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        HStack(spacing: 14) {
            RecordButton()

            // Like Keys, the icon carries the on/off state, since button highlights vanish
            // whenever the window is in the background.
            Button {
                state.togglePresentation()
            } label: {
                Label {
                    Text("Present")
                } icon: {
                    Image(systemName: "macwindow.on.rectangle")
                        .foregroundStyle(state.isPresenting ? Color.accentColor : Color.secondary)
                }
            }
            .disabled(state.isRecording || state.isFinishing)
            .accessibilityValue(state.isPresenting ? "On" : "Off")
            .help(presentHelp)

            Divider().frame(height: 22)

            Picker("Resolution", selection: $state.settings.resolution) {
                ForEach(Resolution.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .disabled(state.isRecording)
            .help("Output resolution")

            Picker("Frame rate", selection: $state.settings.fps) {
                Text("30 fps").tag(30)
                Text("60 fps").tag(60)
            }
            .labelsHidden()
            .fixedSize()
            .disabled(state.isRecording)
            .help("Frame rate")

            Button {
                state.toggleInspector(.background)
            } label: {
                Label("Background", systemImage: "photo")
            }
            .help("Background settings")

            Button {
                state.toggleInspector(.framing)
            } label: {
                Label("Framing", systemImage: "rectangle.inset.filled")
            }
            .help("Window framing settings")

            Button {
                state.toggleInspector(.camera)
            } label: {
                Label("Camera", systemImage: state.cameraVisible ? "video.fill" : "video.slash")
            }
            .help("Camera settings")

            // The icon carries the on/off state: button highlights disappear whenever the window
            // is in the background, which is most of the time on a second screen.
            Button {
                state.toggleInspector(.keystrokes)
            } label: {
                Label {
                    Text("Keys")
                } icon: {
                    Image(systemName: keysIcon)
                        .foregroundStyle(state.settings.keystrokesEnabled ? Color.accentColor : Color.secondary)
                }
            }
            .accessibilityValue(state.settings.keystrokesEnabled ? "On" : "Off")
            .help(state.keystrokeAccessMissing ? "Waiting for Input Monitoring access in System Settings" : "Keystroke overlay settings")

            Spacer(minLength: 0)

            MicControl()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var presentHelp: String {
        if state.isRecording || state.isFinishing {
            return "Stop recording to present"
        }
        return state.isPresenting
            ? "Close the presentation window"
            : "Open a window showing the canvas, to share in a call"
    }

    private var keysIcon: String {
        guard state.settings.keystrokesEnabled else { return "keyboard" }
        return state.keystrokeAccessMissing ? "exclamationmark.triangle.fill" : "keyboard.fill"
    }
}

private struct RecordButton: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 10) {
            Button {
                state.toggleRecording()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: state.isRecording ? "stop.fill" : "record.circle.fill")
                        .foregroundStyle(.red)
                    if state.isRecording, let start = state.recordingStart {
                        TimelineView(.periodic(from: start, by: 1)) { context in
                            Text(Self.elapsed(state.recordedSeconds(at: context.date)))
                                .monospacedDigit()
                                .foregroundStyle(state.isPaused ? .secondary : .primary)
                        }
                    } else {
                        Text(state.isFinishing ? "Saving…" : "Record")
                    }
                }
                .frame(minWidth: 78)
            }
            .controlSize(.large)
            .disabled(state.isFinishing || state.isPresenting)
            .help(recordHelp)

            if state.isRecording {
                Button {
                    state.togglePause()
                } label: {
                    Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                        .frame(minWidth: 12)
                }
                .controlSize(.large)
                .help(pauseHelp)
                .accessibilityLabel(pauseHelp)
            }

            if !state.isRecording, !state.isFinishing, state.lastRecording != nil {
                Button {
                    state.revealLastRecording()
                } label: {
                    Image(systemName: "folder")
                }
                .help("Show the last recording in Finder")
            }
        }
    }

    private var pauseHelp: String {
        state.isPaused ? "Resume recording" : "Pause recording"
    }

    private var recordHelp: String {
        if state.isPresenting { return "Close the presentation window to record" }
        return state.isRecording ? "Stop recording" : "Start recording"
    }

    private static func elapsed(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct MicControl: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        HStack(spacing: 8) {
            if state.micDenied {
                Label("Microphone access is off", systemImage: "mic.slash")
                    .foregroundStyle(.secondary)
                    .help("Allow Wreckingball in System Settings → Privacy & Security → Microphone")
            } else {
                LevelMeter(level: state.micLevel)
                    .frame(width: 56, height: 6)
                Picker("Microphone", selection: $state.settings.micDeviceID) {
                    Text("Default Microphone").tag(String?.none)
                    ForEach(state.mics) { Text($0.name).tag(String?.some($0.id)) }
                }
                .labelsHidden()
                .frame(maxWidth: 190)
                .disabled(state.isRecording)
                .help("Microphone")
            }
        }
    }
}

private struct LevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(level > 0.9 ? Color.red : Color.green)
                    .frame(width: geometry.size.width * CGFloat(level))
            }
        }
        .accessibilityLabel("Microphone level")
    }
}
