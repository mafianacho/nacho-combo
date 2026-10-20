import Carbon.HIToolbox
import Foundation

/// Global hotkeys through Carbon RegisterEventHotKey. This needs no privacy permission;
/// the Accessibility permission is only required to move windows.
final class HotKeyCenter {
    private var handlerRef: EventHandlerRef?
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var callbacks: [UInt32: () -> Void] = [:]
    private(set) var firedCount = 0

    var registeredCount: Int { hotKeys.count }

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, callback: @escaping () -> Void) -> Bool {
        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
                guard let event = event, let userData = userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                            EventParamType(typeEventHotKeyID), nil,
                                            MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                guard err == noErr else { return err }
                Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue().fire(hotKeyID.id)
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
            guard status == noErr else { return false }
        }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E43_4F4D), id: id)  // 'NCOM'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let registered = ref else { return false }
        hotKeys[id] = registered
        callbacks[id] = callback
        return true
    }

    private func fire(_ id: UInt32) {
        firedCount += 1
        callbacks[id]?()
    }

    /// Releases every hotkey and the event handler. After this no key press reaches the app.
    func unregisterAll() {
        for (_, ref) in hotKeys { UnregisterEventHotKey(ref) }
        hotKeys.removeAll()
        callbacks.removeAll()
        if let handler = handlerRef { RemoveEventHandler(handler) }
        handlerRef = nil
    }
}
