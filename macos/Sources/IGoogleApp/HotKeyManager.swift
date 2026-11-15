import Carbon.HIToolbox
import AppKit
import IGoogleCore

/// Глобальные горячие клавиши macOS (Carbon — работают без разрешений спец. возможностей).
/// По умолчанию: ⌃⌥C — отправить буфер, ⌃⌥P — отправить фото из буфера.
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var handler: EventHandlerRef?
    private var configured = false

    private init() {}

    func configure(hub: IGoogleHub) {
        guard !configured else { return }
        configured = true
        register(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey | optionKey)) { [weak hub] in
            hub?.pushCurrentClipboard()
        }
        register(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(controlKey | optionKey)) { [weak hub] in
            hub?.pushClipboardImage()
        }
    }

    private func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        installHandler()
        let id = nextID
        nextID += 1
        actions[id] = action
        let hotKeyID = EventHotKeyID(signature: OSType(0x49476F6F), id: id) // 'IGoo'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs.append(ref)
        }
    }

    private func installHandler() {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            let mgr = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hkID = EventHotKeyID()
            let err = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if err == noErr, let action = mgr.actions[hkID.id] {
                DispatchQueue.main.async { action() }
                return noErr
            }
            return OSStatus(eventNotHandledErr)
        }, 1, &eventType, selfPtr, &handler)
    }
}
