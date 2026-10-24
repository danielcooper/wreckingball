import AppKit
import KeyboardShortcuts

/// Global shortcuts. None are bound by default; the user sets them in Settings.
extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("toggleRecording")
    static let togglePause = Self("togglePause")
    static let nextWindow = Self("nextWindow")
    static let previousWindow = Self("previousWindow")
    static let toggleCamera = Self("toggleCamera")
    static let toggleKeystrokes = Self("toggleKeystrokes")
    static let pinSlots = (1...Pin.maxCount).map { Self("pin\($0)") }
}

@MainActor
enum Hotkeys {
    static func register(_ state: AppState) {
        bind(.toggleRecording, to: .toggleRecording, state)
        bind(.togglePause, to: .togglePause, state)
        bind(.nextWindow, to: .nextWindow, state)
        bind(.previousWindow, to: .previousWindow, state)
        bind(.toggleCamera, to: .toggleCamera, state)
        bind(.toggleKeystrokes, to: .toggleKeystrokes, state)
        for (index, name) in KeyboardShortcuts.Name.pinSlots.enumerated() {
            bind(name, to: .pin(index + 1), state)
        }
    }

    static let all: [KeyboardShortcuts.Name] =
        [.toggleRecording, .togglePause, .nextWindow, .previousWindow, .toggleCamera, .toggleKeystrokes]
        + KeyboardShortcuts.Name.pinSlots

    /// True when a key press is one of Wreckingball's own shortcuts, which the keystroke overlay hides.
    static func isOwnShortcut(keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags) -> Bool {
        let relevant: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        return all.contains { name in
            guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return false }
            return shortcut.carbonKeyCode == Int(keyCode)
                && shortcut.modifiers.intersection(relevant) == modifiers.intersection(relevant)
        }
    }

    private static func bind(_ name: KeyboardShortcuts.Name, to command: Command, _ state: AppState) {
        KeyboardShortcuts.onKeyUp(for: name) { [weak state] in
            Task { @MainActor in state?.perform(command) }
        }
    }
}
