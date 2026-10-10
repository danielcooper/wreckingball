import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// What the keystroke overlay shows. Shared with the render queue.
struct KeystrokeDisplay: Sendable {
    var text = ""
    /// `ProcessInfo.systemUptime` of the last change; the overlay fades out after a pause.
    var updatedAt: TimeInterval = 0
}

/// Watches key presses with a listen-only event tap (Input Monitoring permission) and turns them
/// into overlay text. macOS withholds keys typed into password fields from event taps.
@MainActor
final class KeystrokeMonitor {
    var mode = KeystrokeMode.shortcuts
    /// Returns true for presses that should never be shown, such as Wreckingball's own shortcuts.
    var isExcluded: (CGKeyCode, NSEvent.ModifierFlags) -> Bool = { _, _ in false }
    /// Called with true while access is missing.
    var onAccessChange: ((Bool) -> Void)?

    private let display: Locked<KeystrokeDisplay>
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retryTimer: Timer?

    private var typing = false
    private var lastShortcut: String?
    private var repeatCount = 1

    /// A pause longer than this starts a new group of typed text.
    private static let groupTimeout: TimeInterval = 1.5
    private static let maxTypedLength = 36

    init(display: Locked<KeystrokeDisplay>) {
        self.display = display
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard tap == nil, retryTimer == nil else { return }
        if installTap() { return }
        if !CGPreflightListenEventAccess() {
            CGRequestListenEventAccess()
        }
        onAccessChange?(true)
        // Pick up access as soon as it is granted.
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.installTap() else { return }
                self.retryTimer?.invalidate()
                self.retryTimer = nil
            }
        }
    }

    private func installTap() -> Bool {
        guard CGPreflightListenEventAccess() else {
            Log.keys.notice("Input Monitoring access not granted")
            return false
        }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: keystrokeTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.keys.error("Event tap could not be created")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        onAccessChange?(false)
        Log.keys.notice("Keystroke event tap installed")
        return true
    }

    private func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
        typing = false
        lastShortcut = nil
        display.set(KeystrokeDisplay())
        onAccessChange?(false)
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Log.keys.notice("Event tap was disabled by the system; re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .keyDown,
              event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
              let nsEvent = NSEvent(cgEvent: event)
        else { return }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = nsEvent.modifierFlags.intersection([.command, .control, .option, .shift])
        guard !isExcluded(keyCode, modifiers) else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let recent = now - display.get().updatedAt < Self.groupTimeout

        if modifiers.contains(.command) || modifiers.contains(.control) {
            showShortcut(Self.symbols(for: modifiers) + Self.keyName(keyCode: keyCode, event: nsEvent), recent: recent, now: now)
        } else if mode == .allKeys {
            appendTyped(keyCode: keyCode, event: nsEvent, modifiers: modifiers, recent: recent, now: now)
        }
    }

    private func showShortcut(_ shortcut: String, recent: Bool, now: TimeInterval) {
        if recent, !typing, shortcut == lastShortcut {
            repeatCount += 1
        } else {
            repeatCount = 1
        }
        typing = false
        lastShortcut = shortcut
        let text = repeatCount > 1 ? "\(shortcut) ×\(repeatCount)" : shortcut
        display.set(KeystrokeDisplay(text: text, updatedAt: now))
    }

    private func appendTyped(keyCode: CGKeyCode, event: NSEvent, modifiers: NSEvent.ModifierFlags, recent: Bool, now: TimeInterval) {
        var text = recent && typing ? display.get().text : ""
        lastShortcut = nil

        if Int(keyCode) == kVK_Delete, !text.isEmpty {
            // Mirror editing rather than showing a run of ⌫.
            text.removeLast()
        } else if let special = Self.specialKeys[Int(keyCode)] {
            text += Self.symbols(for: modifiers.subtracting(.shift)) + special
        } else if let characters = event.characters, !characters.isEmpty,
                  characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
            text += characters
        } else {
            return
        }

        typing = true
        if text.count > Self.maxTypedLength {
            text = "…" + text.suffix(Self.maxTypedLength - 1)
        }
        display.set(KeystrokeDisplay(text: text, updatedAt: now))
    }

    // MARK: Formatting

    private static func symbols(for modifiers: NSEvent.ModifierFlags) -> String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result
    }

    private static func keyName(keyCode: CGKeyCode, event: NSEvent) -> String {
        if let special = specialKeys[Int(keyCode)] {
            return special
        }
        if let base = event.characters(byApplyingModifiers: []), !base.isEmpty,
           base.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
            return base.uppercased()
        }
        return "?"
    }

    private static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Tab: "⇥", kVK_Space: "␣",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

/// The event tap runs on the main run loop, so the callback is already on the main thread.
private func keystrokeTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let userInfo {
        let monitor = Unchecked(Unmanaged<KeystrokeMonitor>.fromOpaque(userInfo).takeUnretainedValue())
        let boxed = Unchecked(event)
        MainActor.assumeIsolated {
            monitor.value.handle(type: type, event: boxed.value)
        }
    }
    return Unmanaged.passUnretained(event)
}
