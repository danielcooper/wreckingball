import SwiftUI

@main
struct WreckingballApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState()

    var body: some Scene {
        Window("Wreckingball", id: "main") {
            MainView()
                .environment(state)
                .onOpenURL { state.handle(url: $0) }
        }
        .defaultSize(width: 1180, height: 720)

        Settings {
            SettingsView()
                .environment(state)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
