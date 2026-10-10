import Carbon.HIToolbox
import Foundation

struct HotKeyError: Error {
    let status: OSStatus
}

/// Global hotkey via Carbon `RegisterEventHotKey` (no Accessibility permission needed).
final class HotKey {
    private static let signature: OSType = 0x5343_524E // 'SCRN'
    private static var nextID: UInt32 = 1

    private let id: UInt32
    private let handler: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// - Parameters:
    ///   - keyCode: virtual key code, e.g. `UInt32(kVK_ANSI_2)`.
    ///   - modifiers: Carbon modifier mask, e.g. `UInt32(cmdKey | shiftKey)`.
    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) throws {
        self.id = HotKey.nextID
        HotKey.nextID += 1
        self.handler = handler

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hkID)
            guard status == noErr else { return status }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            guard hkID.signature == HotKey.signature, hkID.id == hotKey.id else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async { hotKey.handler() }
            return noErr
        }

        var status = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType,
                                         Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        guard status == noErr else { throw HotKeyError(status: status) }

        let hkID = EventHotKeyID(signature: HotKey.signature, id: id)
        status = RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            handlerRef = nil
            throw HotKeyError(status: status)
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
