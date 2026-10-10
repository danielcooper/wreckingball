import Foundation

/// A pinned window. Window IDs do not survive a relaunch, so pins match on app and title.
struct Pin: Codable, Equatable, Identifiable {
    var id = UUID()
    var bundleID: String
    var appName: String
    var title: String

    static let maxCount = 9
    private static let defaultsKey = "pins"

    func matches(_ window: WindowInfo) -> Bool {
        window.bundleID == bundleID && window.title == title
    }

    /// The exact window if it is open, otherwise the app's frontmost window.
    func resolve(in windows: [WindowInfo]) -> WindowInfo? {
        windows.first(where: matches)
            ?? windows.first { $0.bundleID == bundleID }
    }

    static func load() -> [Pin] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let pins = try? JSONDecoder().decode([Pin].self, from: data)
        else { return [] }
        return pins
    }

    static func save(_ pins: [Pin]) {
        guard let data = try? JSONEncoder().encode(pins) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
