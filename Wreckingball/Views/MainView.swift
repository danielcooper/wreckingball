import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        HStack(spacing: 0) {
            VStack(spacing: 0) {
                CanvasPreview()
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                ControlBar()
            }
            Divider()
            // Settings that need the preview free for dragging slide in over the window list.
            ZStack {
                WindowPickerView()
                if let inspector = state.inspector {
                    InspectorPanel(inspector: inspector)
                        .transition(.move(edge: .trailing))
                }
            }
            .frame(width: 270)
            .clipped()
            .animation(.snappy(duration: 0.25), value: state.inspector == nil)
        }
        .frame(minWidth: 940, minHeight: 520)
        .alert("Wreckingball", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("OK") { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }
}

/// The live canvas. Dragging the camera moves it; while the keystroke popover is open, so does
/// dragging the keystroke pill.
private struct CanvasPreview: View {
    @Environment(AppState.self) private var state
    @State private var drag: DragTarget?

    private enum DragTarget {
        /// Offset from the pointer to the dragged item's centre, in view points.
        case camera(CGSize)
        case keystrokes(CGSize)
        case nothing
    }

    var body: some View {
        let canvas = state.settings.canvasSize

        PreviewView(layer: state.engine.previewLayer)
            .aspectRatio(canvas.width / canvas.height, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(state.isRecording ? Color.red : Color.primary.opacity(0.15), lineWidth: state.isRecording ? 2 : 1)
            }
            .overlay {
                GeometryReader { geometry in
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(dragGesture(in: geometry.size))
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if drag == nil {
                    drag = target(at: value.startLocation, in: size)
                }
                switch drag {
                case .camera(let offset):
                    moveCamera(to: value.location, offset: offset, in: size)
                case .keystrokes(let offset):
                    moveKeystrokes(to: value.location, offset: offset, in: size)
                case .nothing, nil:
                    break
                }
            }
            .onEnded { _ in drag = nil }
    }

    private func target(at point: CGPoint, in size: CGSize) -> DragTarget {
        if state.editingKeystrokes, let rect = state.engine.keystrokeRect.get() {
            let frame = CGRect(x: rect.minX * size.width, y: rect.minY * size.height, width: rect.width * size.width, height: rect.height * size.height)
            if frame.insetBy(dx: -6, dy: -6).contains(point) {
                return .keystrokes(CGSize(width: frame.midX - point.x, height: frame.midY - point.y))
            }
        }
        let settings = state.settings
        if state.cameraVisible {
            let half = cameraHalfSize(in: size)
            let center = CGPoint(x: settings.cameraCenter.x * size.width, y: settings.cameraCenter.y * size.height)
            if abs(center.x - point.x) <= half.width, abs(center.y - point.y) <= half.height {
                return .camera(CGSize(width: center.x - point.x, height: center.y - point.y))
            }
        }
        return .nothing
    }

    private func cameraHalfSize(in size: CGSize) -> CGSize {
        let settings = state.settings
        return CGSize(
            width: settings.cameraSize * size.height * settings.cameraShape.aspect / 2,
            height: settings.cameraSize * size.height / 2
        )
    }

    private func moveCamera(to location: CGPoint, offset: CGSize, in size: CGSize) {
        // Keep the camera inside the canvas with a small margin.
        let half = cameraHalfSize(in: size)
        let margin = size.height * 0.02
        let x = min(max(location.x + offset.width, half.width + margin), size.width - half.width - margin)
        let y = min(max(location.y + offset.height, half.height + margin), size.height - half.height - margin)
        state.settings.cameraCenter = CGPoint(x: x / size.width, y: y / size.height)
    }

    private func moveKeystrokes(to location: CGPoint, offset: CGSize, in size: CGSize) {
        let rect = state.engine.keystrokeRect.get() ?? .zero
        let half = CGSize(width: rect.width * size.width / 2, height: rect.height * size.height / 2)
        let x = min(max(location.x + offset.width, half.width), size.width - half.width)
        let y = min(max(location.y + offset.height, half.height), size.height - half.height)
        state.settings.keystrokeCenter = CGPoint(x: x / size.width, y: y / size.height)
    }
}
