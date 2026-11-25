import AppKit
import SwiftUI

struct WindowPickerView: View {
    @Environment(AppState.self) private var state
    @State private var query = ""
    @FocusState private var searching: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Windows")
                    .font(.headline)
                Spacer()
                Button("Clear") { state.select(nil) }
                    .buttonStyle(.link)
                    .disabled(state.selectedWindowID == nil)
                    .help("Show only the background")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, hasSources ? 8 : 10)

            if hasSources {
                searchField
            }
            Divider()

            if state.catalog.permissionDenied {
                PermissionNotice()
            } else if !hasSources {
                ContentUnavailableView("No windows", systemImage: "macwindow", description: Text("Open a window to present it."))
            } else if matches.isEmpty, matchingDisplays.isEmpty {
                // ContentUnavailableView is sized for a whole window; in a column this narrow it
                // ends up floating in the middle, so the message sits where the list would start.
                Text("No windows match “\(query)”.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.top, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        pinnedSection
                        ForEach(groups(of: matches), id: \.name) { group in
                            AppHeader(name: group.name, pid: group.windows[0].pid)
                            ForEach(group.windows) { window in
                                WindowRow(window: window, slot: nil)
                            }
                        }
                        displaysSection
                    }
                    .padding(12)
                }
            }
        }
        .background(.background.secondary)
    }

    private var hasSources: Bool {
        !state.catalog.permissionDenied && !(state.catalog.windows.isEmpty && state.catalog.displays.isEmpty)
    }

    /// Whole desktops, below the windows: the thing to reach for when a demo spans several apps.
    @ViewBuilder
    private var displaysSection: some View {
        if !matchingDisplays.isEmpty {
            if !matches.isEmpty {
                Divider()
                    .padding(.vertical, 4)
            }
            Label("Displays", systemImage: "display")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            ForEach(matchingDisplays) { display in
                DisplayRow(display: display)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .focused($searching)
                .onSubmit {
                    // Return presents the first match, so finding a window never needs the mouse.
                    if let first = matches.first { state.select(first) }
                }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear the search")
            }
        }
        .font(.callout)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.background, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.primary.opacity(searching ? 0.25 : 0.1))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    /// Windows matching the search, by app name and window title. Every word has to appear
    /// somewhere, so "chrome git" narrows to the Chrome window with the repo open.
    private var matches: [WindowInfo] {
        let terms = query.split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return state.catalog.windows }
        return state.catalog.windows.filter { window in
            matches(terms, in: "\(window.appName) \(window.title)")
        }
    }

    /// Displays answer to their name and to the words someone is likely to type looking for one.
    private var matchingDisplays: [DisplayInfo] {
        let terms = query.split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return state.catalog.displays }
        return state.catalog.displays.filter { display in
            matches(terms, in: "\(display.name) display desktop screen")
        }
    }

    private func matches(_ terms: [Substring], in text: String) -> Bool {
        terms.allSatisfy { text.localizedStandardContains($0) }
    }

    /// Hidden while searching: the matches are the whole point of the list then.
    @ViewBuilder
    private var pinnedSection: some View {
        if !state.pins.isEmpty, query.isEmpty {
            Label("Pinned", systemImage: "pin.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(state.pins.enumerated()), id: \.element.id) { index, pin in
                if let window = pin.resolve(in: state.catalog.windows) {
                    WindowRow(window: window, slot: index + 1)
                } else {
                    MissingPinRow(pin: pin, slot: index + 1)
                }
            }
            Divider()
                .padding(.vertical, 4)
        }
    }

    private func groups(of windows: [WindowInfo]) -> [(name: String, windows: [WindowInfo])] {
        var result: [(name: String, windows: [WindowInfo])] = []
        for window in windows {
            if let last = result.indices.last, result[last].name == window.appName {
                result[last].windows.append(window)
            } else {
                result.append((window.appName, [window]))
            }
        }
        return result
    }
}

private struct AppHeader: View {
    let name: String
    let pid: pid_t

    var body: some View {
        HStack(spacing: 6) {
            if let icon = NSRunningApplication(processIdentifier: pid)?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
            }
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.top, 4)
    }
}

private struct WindowRow: View {
    @Environment(AppState.self) private var state
    let window: WindowInfo
    let slot: Int?
    @State private var hovering = false

    var body: some View {
        let isLive = state.selectedWindowID == window.id
        let isPinned = state.isPinned(window)

        Button {
            state.select(window)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                thumbnail
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .background(.black.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 4) {
                            if let slot {
                                Badge(text: "\(slot)", color: .gray)
                            }
                            if isLive {
                                Badge(text: "LIVE", color: .red)
                            }
                        }
                        .padding(6)
                    }
                Text(slot == nil ? window.title : "\(window.appName): \(window.title)")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(6)
            .background(isLive ? Color.accentColor.opacity(0.18) : hovering ? Color.primary.opacity(0.06) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isLive ? Color.accentColor : .clear, lineWidth: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if hovering || isPinned {
                Button {
                    state.togglePin(window)
                } label: {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.caption)
                        .padding(5)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(12)
                .help(isPinned ? "Unpin" : "Pin")
            }
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button(isPinned ? "Unpin" : "Pin") { state.togglePin(window) }
        }
        .help(window.title)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = state.catalog.thumbnails[window.id] {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "macwindow")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
        }
    }
}

/// A whole desktop. Like a window tile, without pinning: pins match on app and title.
private struct DisplayRow: View {
    @Environment(AppState.self) private var state
    let display: DisplayInfo
    @State private var hovering = false

    var body: some View {
        let isLive = state.selectedDisplayID == display.id

        Button {
            state.select(display: display)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                thumbnail
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .background(.black.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(alignment: .topLeading) {
                        if isLive {
                            Badge(text: "LIVE", color: .red)
                                .padding(6)
                        }
                    }
                Text(display.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(6)
            .background(isLive ? Color.accentColor.opacity(0.18) : hovering ? Color.primary.opacity(0.06) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isLive ? Color.accentColor : .clear, lineWidth: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(display.name) — \(Int(display.size.width)) × \(Int(display.size.height))")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = state.catalog.displayThumbnails[display.id] {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "display")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct MissingPinRow: View {
    @Environment(AppState.self) private var state
    let pin: Pin
    let slot: Int

    var body: some View {
        HStack(spacing: 6) {
            Badge(text: "\(slot)", color: .gray)
            Text("\(pin.appName): \(pin.title)")
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                state.pins.removeAll { $0.id == pin.id }
            } label: {
                Image(systemName: "pin.slash")
            }
            .buttonStyle(.plain)
            .help("Unpin")
        }
        .foregroundStyle(.secondary)
        .padding(6)
        .help("Not open")
    }
}

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: Capsule())
    }
}

private struct PermissionNotice: View {
    var body: some View {
        ContentUnavailableView {
            Label("Screen Recording access needed", systemImage: "lock.display")
        } description: {
            Text("Allow Wreckingball in System Settings → Privacy & Security → Screen & System Audio Recording, then relaunch.")
        } actions: {
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
