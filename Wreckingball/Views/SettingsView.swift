import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutSettings()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            RemoteSettings()
                .tabItem { Label("Stream Deck", systemImage: "square.grid.3x3") }
        }
        .frame(width: 520)
    }
}

private struct GeneralSettings: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        Form {
            LabeledContent("Save recordings to") {
                HStack {
                    Text(state.outputFolder.path(percentEncoded: false))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(.secondary)
                    Button("Choose…") { state.chooseOutputFolder() }
                }
            }
            Picker("Video codec", selection: $state.settings.codec) {
                ForEach(VideoCodec.allCases) { Text($0.label).tag($0) }
            }
            .disabled(state.isRecording)
            Toggle("Bring the app to the front when switching windows", isOn: $state.settings.activateOnSwitch)
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutSettings: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Start or stop recording", name: .toggleRecording)
                KeyboardShortcuts.Recorder("Next window", name: .nextWindow)
                KeyboardShortcuts.Recorder("Previous window", name: .previousWindow)
                KeyboardShortcuts.Recorder("Show or hide camera", name: .toggleCamera)
                KeyboardShortcuts.Recorder("Show or hide keystrokes", name: .toggleKeystrokes)
            } footer: {
                Text("Shortcuts work while any app is in front. Next and previous step through your pinned windows, or all windows if none are pinned.")
            }
            Section("Pinned windows") {
                ForEach(Array(KeyboardShortcuts.Name.pinSlots.enumerated()), id: \.offset) { index, name in
                    KeyboardShortcuts.Recorder("Pinned window \(index + 1)", name: name)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 480)
    }
}

private struct RemoteSettings: View {
    var body: some View {
        Form {
            Section {
                ForEach(Command.documentation, id: \.url) { entry in
                    LabeledContent(entry.action) {
                        Text(entry.url)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            } header: {
                Text("URL commands")
            } footer: {
                Text("For a Stream Deck, the simplest route is a Hotkey action that presses a shortcut you set in the Shortcuts tab. URL commands also work, but opening one normally brings Wreckingball to the front; run `open -g \"wreckingball://pin/1\"` to keep the presented app focused.")
            }
        }
        .formStyle(.grouped)
    }
}
