import SwiftUI
import AppKit
import IGoogleCore

struct SettingsView: View {
    @EnvironmentObject var hub: IGoogleHub
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Параметры").font(.title2.bold())
                Spacer()
                Button("Готово") { dismiss() }.keyboardShortcut(.defaultAction)
            }

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

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Куда сохранять фото с Pixel").font(.headline)
                HStack {
                    Image(systemName: "folder")
                    Text(hub.photoSaveDirectory?.path ?? "~/Downloads/IGoogle")
                        .lineLimit(1).truncationMode(.middle).foregroundColor(.secondary)
                    Spacer()
                    Button("Выбрать…") { pickFolder() }
                    if hub.photoSaveDirectory != nil {
                        Button("Сбросить") { hub.photoSaveDirectory = nil }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Горячие клавиши").font(.headline)
                hotkeyRow("Отправить буфер", "⌃⌥C")
                hotkeyRow("Отправить фото из буфера", "⌃⌥P")
                Text("Скоро можно будет переназначить.").font(.caption).foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 440, height: 420)
    }

    private func hotkeyRow(_ title: String, _ keys: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Выбрать"
        if panel.runModal() == .OK, let url = panel.url {
            hub.photoSaveDirectory = url
        }
    }
}
