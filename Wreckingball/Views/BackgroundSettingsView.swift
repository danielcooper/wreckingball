import AppKit
import SwiftUI

struct BackgroundSettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        let background = $state.settings.background

        Form {
            Section {
                Picker("Type", selection: background.kind) {
                    ForEach(BackgroundKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            switch state.settings.background.kind {
            case .gradient:
                Section("Presets") {
                    PresetGrid()
                }
                Section("Gradient") {
                    Picker("Style", selection: background.gradientKind) {
                        ForEach(GradientKind.allCases) { Text($0.label).tag($0) }
                    }
                    ForEach(state.settings.background.colors.indices, id: \.self) { index in
                        ColorPicker(colorLabel(index), selection: cgColor(background.colors[index]), supportsOpacity: false)
                    }
                    HStack {
                        Button("Add Colour") {
                            let last = state.settings.background.colors.last ?? RGBAColor(red: 1, green: 1, blue: 1)
                            state.settings.background.colors.append(last)
                        }
                        .disabled(state.settings.background.colors.count >= BackgroundSettings.colorStopRange.upperBound)
                        Button("Remove") {
                            state.settings.background.colors.removeLast()
                        }
                        .disabled(state.settings.background.colors.count <= BackgroundSettings.colorStopRange.lowerBound)
                    }
                    if state.settings.background.gradientKind == .linear {
                        Slider(value: background.angle, in: 0...360, step: 5) {
                            Text("Angle")
                        }
                    }
                }

            case .solid:
                Section {
                    ColorPicker("Colour", selection: cgColor(background.solidColor), supportsOpacity: false)
                }

            case .image:
                Section("Image") {
                    if let path = state.settings.background.imagePath {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                    Button("Choose Image…") { state.chooseBackground() }
                    Button("Use Desktop Picture") { state.useDesktopPicture() }
                    Slider(value: background.imageBlur, in: 0...60) {
                        Text("Blur")
                    }
                    Slider(value: background.imageDim, in: 0...0.8) {
                        Text("Dim")
                    }
                }
            }

            Section("Effects") {
                Slider(value: background.vignette, in: 0...1) {
                    Text("Vignette")
                }
                Slider(value: background.grain, in: 0...1) {
                    Text("Grain")
                }
            }

            Section {
                Button("Reset Background") {
                    state.settings.background = BackgroundSettings()
                }
            }
        }
    }

    private func colorLabel(_ index: Int) -> String {
        let count = state.settings.background.colors.count
        if state.settings.background.gradientKind == .aurora {
            return index == 0 ? "Base" : "Glow \(index)"
        }
        if index == 0 { return "Start" }
        if index == count - 1 { return "End" }
        return "Middle"
    }

    private func cgColor(_ binding: Binding<RGBAColor>) -> Binding<CGColor> {
        Binding(
            get: { binding.wrappedValue.cgColor },
            set: { binding.wrappedValue = RGBAColor($0) }
        )
    }
}

/// Clickable thumbnails of the gradient presets.
private struct PresetGrid: View {
    @Environment(AppState.self) private var state

    private static let swatches: [String: NSImage] = {
        var result: [String: NSImage] = [:]
        let size = CGSize(width: 160, height: 90)
        for preset in BackgroundPreset.all {
            var settings = BackgroundSettings()
            settings.apply(preset)
            if let image = BackgroundRenderer.gradient(settings, size: size) {
                result[preset.id] = NSImage(cgImage: image, size: NSSize(width: 80, height: 45))
            }
        }
        return result
    }()

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(BackgroundPreset.all) { preset in
                let selected = state.settings.background.matches(preset)
                Button {
                    state.settings.background.apply(preset)
                } label: {
                    Group {
                        if let swatch = Self.swatches[preset.id] {
                            Image(nsImage: swatch)
                                .resizable()
                        } else {
                            Color.gray
                        }
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: selected ? 2 : 1)
                    }
                }
                .buttonStyle(.plain)
                .help(preset.name)
                .accessibilityLabel(preset.name)
            }
        }
        .padding(.vertical, 2)
    }
}
