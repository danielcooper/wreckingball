import AppKit
import Observation
@preconcurrency import ScreenCaptureKit

struct WindowInfo: Identifiable {
    let id: CGWindowID
    let title: String
    let appName: String
    let bundleID: String
    let pid: pid_t
    let window: SCWindow
}

/// Polls ScreenCaptureKit for windows that can be presented. A window is only listed once a
/// test capture of it has produced a non-blank image, so every tile in the picker works.
@MainActor
@Observable
final class WindowCatalog {
    private(set) var windows: [WindowInfo] = []
    private(set) var thumbnails: [CGWindowID: NSImage] = [:]
    private(set) var permissionDenied = false

    @ObservationIgnored var onUpdate: (() -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastAttempt: [CGWindowID: Date] = [:]
    @ObservationIgnored private var failures: [CGWindowID: Int] = [:]
    @ObservationIgnored private var requestedAccess = false

    /// How often an already-listed window's thumbnail is refreshed, and a failing window retried.
    private static let thumbnailInterval: TimeInterval = 3
    /// Consecutive failed captures before a listed window is dropped.
    private static let maxFailures = 2

    /// System UI that reports ordinary windows but is never something to present.
    private static let excludedBundleIDs: Set<String> = [
        "com.apple.universalaccessAuthWarn",
        "com.apple.UserNotificationCenter",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.dock",
        "com.apple.WindowManager",
        "com.apple.loginwindow",
        "com.apple.Spotlight",
        "com.apple.screencaptureui",
        "com.apple.SecurityAgent",
        "com.apple.coreservices.uiagent",
        "com.apple.TextInputMenuAgent",
        "com.apple.wallpaper.agent",
    ]

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func window(id: CGWindowID?) -> WindowInfo? {
        guard let id else { return nil }
        return windows.first { $0.id == id }
    }

    private func refresh() async {
        // Every ScreenCaptureKit call made without access re-shows the system prompt, so check
        // quietly first and ask at most once per launch.
        guard CGPreflightScreenCaptureAccess() else {
            if !requestedAccess {
                requestedAccess = true
                CGRequestScreenCaptureAccess()
            }
            windows = []
            permissionDenied = true
            onUpdate?()
            return
        }

        let candidates: [WindowInfo]
        do {
            candidates = try await fetchCandidates()
            permissionDenied = false
        } catch {
            Log.capture.error("Listing windows failed: \(error.localizedDescription)")
            windows = []
            onUpdate?()
            return
        }

        let candidateIDs = Set(candidates.map(\.id))
        thumbnails = thumbnails.filter { candidateIDs.contains($0.key) }
        lastAttempt = lastAttempt.filter { candidateIDs.contains($0.key) }
        failures = failures.filter { candidateIDs.contains($0.key) }

        // New windows are tested straight away; known ones are refreshed less often.
        let now = Date()
        for info in candidates {
            if Task.isCancelled { return }
            if let last = lastAttempt[info.id], now.timeIntervalSince(last) < Self.thumbnailInterval { continue }
            lastAttempt[info.id] = now
            if let image = await capture(info) {
                thumbnails[info.id] = image
                failures[info.id] = nil
            } else {
                let count = (failures[info.id] ?? 0) + 1
                failures[info.id] = count
                if thumbnails[info.id] == nil || count >= Self.maxFailures {
                    thumbnails[info.id] = nil
                }
            }
        }

        windows = candidates.filter { thumbnails[$0.id] != nil }
        onUpdate?()
    }

    private func fetchCandidates() async throws -> [WindowInfo] {
        // On-screen only: minimised windows, hidden apps and other Spaces deliver no frames.
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let ownBundleID = Bundle.main.bundleIdentifier
        let found = content.windows.compactMap { window -> WindowInfo? in
            guard window.windowLayer == 0,
                  window.isOnScreen,
                  let app = window.owningApplication,
                  app.bundleIdentifier != ownBundleID,
                  !Self.excludedBundleIDs.contains(app.bundleIdentifier),
                  !app.applicationName.isEmpty,
                  let title = window.title, !title.isEmpty,
                  window.frame.width >= 120, window.frame.height >= 120
            else { return nil }
            return WindowInfo(
                id: window.windowID,
                title: title,
                appName: app.applicationName,
                bundleID: app.bundleIdentifier,
                pid: app.processID,
                window: window
            )
        }
        // Stable sort by app keeps each app's windows in front-to-back order.
        let byApp = Dictionary(grouping: found, by: \.appName)
        return byApp.keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .flatMap { byApp[$0] ?? [] }
    }

    /// Captures a small image of the window, or nil if capture failed or came back blank.
    private func capture(_ info: WindowInfo) async -> NSImage? {
        let frame = info.window.frame
        guard frame.width > 0, frame.height > 0 else { return nil }
        let configuration = SCStreamConfiguration()
        configuration.width = 360
        configuration.height = max(2, Int(360 * frame.height / frame.width))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let filter = SCContentFilter(desktopIndependentWindow: info.window)
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration),
              !Self.isBlank(image)
        else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    /// ScreenCaptureKit returns fully transparent or solid black images for windows it cannot
    /// actually capture. Sample a tiny copy and treat either case as a failure.
    private static func isBlank(_ image: CGImage) -> Bool {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return true }

        var maxAlpha: UInt8 = 0
        var maxColour: UInt8 = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            maxColour = max(maxColour, pixels[index], pixels[index + 1], pixels[index + 2])
            maxAlpha = max(maxAlpha, pixels[index + 3])
        }
        return maxAlpha < 8 || maxColour < 4
    }
}
