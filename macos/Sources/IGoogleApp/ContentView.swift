import SwiftUI
import IGoogleCore

struct ContentView: View {
    @EnvironmentObject var hub: IGoogleHub
    @State private var flash = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            background
            ScrollView {
                VStack(spacing: 18) {
                    header
                    devicesSection
                    clipboardSection
                    dropZone
                }
                .padding(20)
            }
        }
        .frame(minWidth: 460, minHeight: 660)
        .onAppear {
            try? hub.start()
            HotKeyManager.shared.configure(hub: hub)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(hub)
        }
    }

    // MARK: Фон («liquid glass»)

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.12, blue: 0.18),
                         Color(red: 0.05, green: 0.06, blue: 0.10)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(Color(red: 0.29, green: 0.52, blue: 0.96).opacity(0.35))
                .frame(width: 340, height: 340)
                .blur(radius: 120)
                .offset(x: -160, y: -200)
            Circle()
                .fill(Color(red: 0.55, green: 0.33, blue: 0.95).opacity(0.30))
                .frame(width: 320, height: 320)
                .blur(radius: 140)
                .offset(x: 180, y: 220)
            Rectangle().fill(.ultraThinMaterial)
        }
        .ignoresSafeArea()
    }

    // MARK: Шапка

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(white: 1.0), Color(white: 0.62)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                Text("G")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(white: 0.15))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("IGoogle")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Pixel → MacBook")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill").font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .padding(8)
            .background(.ultraThinMaterial, in: Circle())
            HStack(spacing: 6) {
                Circle()
                    .fill(hub.isRunning ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(hub.isRunning ? "активно" : "остановлено")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    // MARK: Устройства

    private var devicesSection: some View {
        glassPanel {
            VStack(alignment: .leading, spacing: 10) {
                Label("Устройства", systemImage: "laptopcomputer.and.iphone")
                    .font(.headline)
                if hub.peers.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Ожидание Pixel…").foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                    .transition(.opacity)
                }
                ForEach(hub.peers) { peer in
                    DeviceRow(peer: peer)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: hub.peers)
    }

    // MARK: Буфер обмена

    private var clipboardSection: some View {
        glassPanel {
            VStack(alignment: .leading, spacing: 10) {
                Label("Буфер обмена", systemImage: "doc.on.clipboard")
                    .font(.headline)
                Text(hub.lastTransfer ?? "Скопируйте текст на Mac или Pixel — он появится здесь.")
                    .font(.system(.body, design: .rounded))
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .foregroundColor(hub.lastTransfer == nil ? .secondary : .primary)
                HStack {
                    Text(relativeTime(hub.lastTransferAt))
                        .font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { flash = true }
                        hub.pushCurrentClipboard()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation { flash = false }
                        }
                    } label: {
                        Label("Отправить на Pixel", systemImage: "arrow.up.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(flash ? Color.accentColor : .clear, lineWidth: 2))
        .scaleEffect(flash ? 1.015 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: flash)
    }

    // MARK: Drop-зона

    private var dropZone: some View {
        glassPanel {
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 30))
                    .foregroundColor(.secondary)
                Text("Перетащите файл — или на Pixel нажмите «Поделиться → Отправить на MacBook»")
                    .font(.caption).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.4),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            providers.first?.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                hub.sendFile(url)
            }
            return true
        }
    }

    // MARK: Настройки

    private var settingsSection: some View {
        glassPanel {
            VStack(alignment: .leading, spacing: 10) {
                Label("Настройки", systemImage: "slider.horizontal.3").font(.headline)
                Toggle(isOn: Binding(get: { hub.receiveClipboard }, set: { hub.receiveClipboard = $0 })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Общий буфер обмена")
                        Text("Принимать текст с Pixel автоматически")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                Toggle(isOn: Binding(get: { hub.seamlessMode }, set: { hub.seamlessMode = $0 })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Бесшовный режим")
                        Text("Keep-alive и авто-переподключение")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Helpers

    private func glassPanel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
    }

    private func relativeTime(_ date: Date?) -> String {
        guard let date else { return "ещё ничего" }
        let s = Int(Date().timeIntervalSince(date))
        if s < 5 { return "только что" }
        if s < 60 { return "\(s) с назад" }
        return "\(s / 60) мин назад"
    }
}

// MARK: - Строка устройства

struct DeviceRow: View {
    let peer: Peer

    var body: some View {
        HStack(spacing: 12) {
            StatusDot(connected: peer.connected)
            VStack(alignment: .leading, spacing: 2) {
                Text(peer.name).font(.system(.body, design: .rounded))
                Text(peer.platform == .android ? "Android · Pixel" : "Mac")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: peer.platform == .android ? "smartphone" : "laptopcomputer")
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct StatusDot: View {
    let connected: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            if connected {
                Circle()
                    .fill(Color.green.opacity(0.35))
                    .frame(width: 16, height: 16)
                    .scaleEffect(pulse ? 1.7 : 1.0)
                    .opacity(pulse ? 0 : 0.7)
                    .animation(.easeOut(duration: 1.1).repeatForever(autoreverses: false), value: pulse)
            }
            Circle()
                .fill(connected ? Color.green : Color.gray)
                .frame(width: 10, height: 10)
        }
        .frame(width: 20, height: 20)
        .onAppear { pulse = true }
    }
}
