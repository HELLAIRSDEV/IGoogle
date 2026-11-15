import SwiftUI
import AppKit
import IGoogleCore

@main
struct IGoogleApp: App {
    @StateObject private var hub = IGoogleHub()

    init() {
        NotchToast.shared.install()
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(hub)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        // «G» в строке меню (трее).
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(hub)
        } label: {
            Text("G")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
        }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var hub: IGoogleHub

    var body: some View {
        Text(hub.isRunning ? "IGoogle · активен" : "IGoogle · остановлен")
        if !hub.peers.isEmpty {
            Text("Устройства: \(hub.peers.count)")
        }
        Divider()
        Button("Открыть окно") {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
        Button("Отправить буфер на Pixel") {
            hub.pushCurrentClipboard()
        }
        Button("Отправить фото из буфера") {
            hub.pushClipboardImage()
        }
        Divider()
        Button("Выход") {
            NSApp.terminate(nil)
        }
    }
}
