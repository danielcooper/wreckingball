import AppKit
import SwiftUI

struct WindowPickerView: View {
    @Environment(AppState.self) private var state

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
            .padding(.vertical, 10)
            Divider()

            if state.catalog.permissionDenied {
                PermissionNotice()
            } else if state.catalog.windows.isEmpty {
                ContentUnavailableView("No windows", systemImage: "macwindow", description: Text("Open a window to present it."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        pinnedSection
                        ForEach(groups, id: \.name) { group in
                            AppHeader(name: group.name, pid: group.windows[0].pid)
                            ForEach(group.windows) { window in
                                WindowRow(window: window, slot: nil)
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(.background.secondary)
    }

    @ViewBuilder
    private var pinnedSection: some View {
        if !state.pins.isEmpty {
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

    private var groups: [(name: String, windows: [WindowInfo])] {
        var result: [(name: String, windows: [WindowInfo])] = []
        for window in state.catalog.windows {
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
