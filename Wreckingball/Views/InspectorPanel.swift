import AppKit
import SwiftUI

/// Which settings panel is showing over the window list.
enum Inspector: Equatable {
    case background, framing, camera, keystrokes

    var title: String {
        switch self {
        case .background: "Background"
        case .framing: "Framing"
        case .camera: "Camera"
        case .keystrokes: "Keystrokes"
        }
    }
}

/// Settings that slide in over the window list, so the preview stays uncovered and items on it
/// can be dragged while adjusting them.
struct InspectorPanel: View {
    @Environment(AppState.self) private var state
    let inspector: Inspector

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(inspector.title)
                    .font(.headline)
                Spacer()
                Button("Done") { state.inspector = nil }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Divider()

            Group {
                switch inspector {
                case .background: BackgroundSettingsView()
                case .framing: FramingSettings()
                case .camera: CameraSettings()
                case .keystrokes: KeystrokeSettings()
                }
            }
            .formStyle(.grouped)
        }
        .background(.background)
    }
}

// MARK: - Framing

private struct FramingSettings: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        Form {
            Section {
                Slider(value: $state.settings.windowPadding, in: 0...0.2) {
                    Text("Padding")
                }
                Slider(value: $state.settings.windowCornerRadius, in: 0...48) {
                    Text("Corners")
                }
                Toggle("Shadow", isOn: $state.settings.windowShadow)
            }
        }
    }
}

// MARK: - Camera

private struct CameraSettings: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        Form {
            Section {
                Toggle("Show when recording", isOn: $state.settings.cameraWhenRecording)
                Toggle("Show when presenting", isOn: $state.settings.cameraWhenPresenting)
                if !state.cameraDenied {
                    Picker("Camera", selection: $state.settings.cameraDeviceID) {
                        Text("System Default").tag(String?.none)
                        ForEach(state.cameras) { Text($0.name).tag(String?.some($0.id)) }
                    }
                }
            } footer: {
                if state.cameraDenied {
                    Text("Camera access is off. Allow Wreckingball in System Settings → Privacy & Security → Camera.")
                } else {
                    Text("In a call your camera usually has a tile of its own, so presenting leaves it off.")
                }
            }

            Section {
                LabeledContent("Shape") {
                    HStack(spacing: 4) {
                        ForEach(CameraShape.allCases) { shape in
                            ShapeButton(shape: shape, isSelected: state.settings.cameraShape == shape) {
                                state.settings.cameraShape = shape
                            }
                        }
                    }
                }
                Slider(value: $state.settings.cameraSize, in: 0.12...0.6) {
                    Text("Size")
                }
                Toggle("Mirror", isOn: $state.settings.cameraMirrored)
            } footer: {
                Text("Drag the camera in the preview to move it.")
            }
        }
        .onAppear { state.refreshDevices() }
    }
}

private struct ShapeButton: View {
    let shape: CameraShape
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ShapeOutline(shape: shape)
                .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))
                .frame(width: 18 * min(shape.aspect, 1.3), height: 18)
                .padding(4)
                .background(isSelected ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(shape.label)
        .accessibilityLabel(shape.label)
    }
}

private struct ShapeOutline: Shape {
    let shape: CameraShape

    func path(in rect: CGRect) -> Path {
        Path(shape.path(in: rect))
    }
}

// MARK: - Keystrokes

private struct KeystrokeSettings: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        let style = $state.settings.keystrokeStyle

        Form {
            Section {
                Toggle("Show keystrokes", isOn: $state.settings.keystrokesEnabled)
                Picker("Show", selection: $state.settings.keystrokeMode) {
                    ForEach(KeystrokeMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } footer: {
                if state.keystrokeAccessMissing {
                    Text("Waiting for access. Allow Wreckingball in System Settings → Privacy & Security → Input Monitoring.")
                }
            }

            Section("Text") {
                Picker("Font", selection: style.font) {
                    ForEach(KeystrokeStyle.systemDesigns, id: \.tag) { Text($0.label).tag($0.tag) }
                    Divider()
                    ForEach(Self.fontFamilies, id: \.self) { Text($0).tag($0) }
                }
                Slider(value: style.fontSize, in: 20...90) {
                    Text("Size")
                }
                Toggle("Bold", isOn: style.bold)
                ColorPicker("Colour", selection: cgColor(style.textColor), supportsOpacity: false)
            }

            Section("Pill") {
                ColorPicker("Background", selection: cgColor(style.backgroundColor), supportsOpacity: true)
                Slider(value: style.outlineWidth, in: 0...8) {
                    Text("Outline")
                }
                ColorPicker("Outline colour", selection: cgColor(style.outlineColor), supportsOpacity: true)
                    .disabled(state.settings.keystrokeStyle.outlineWidth == 0)
            }

            Section {
                Button("Reset Style and Position") {
                    state.settings.keystrokeStyle = KeystrokeStyle()
                    state.settings.keystrokeCenter = CanvasSettings().keystrokeCenter
                }
            } footer: {
                Text(state.isRecording
                    ? "The sample is hidden while recording."
                    : "Drag the sample on the preview to move it. It is never recorded.")
            }
        }
    }

    private static let fontFamilies = NSFontManager.shared.availableFontFamilies
        .filter { !$0.hasPrefix(".") }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

    private func cgColor(_ binding: Binding<RGBAColor>) -> Binding<CGColor> {
        Binding(
            get: { binding.wrappedValue.cgColor },
            set: { binding.wrappedValue = RGBAColor($0) }
        )
    }
}
