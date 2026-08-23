import Carbon.HIToolbox
import OSLog

@MainActor
final class GlobalRunShortcut {
    private static let logger = Logger(subsystem: "app.amorfati.Run", category: "GlobalShortcut")
    private static let signature: OSType = 0x52756E52 // "RunR"
    private static let identifier: UInt32 = 1

    private let action: () -> Void
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func register() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }

                var hotKeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard parameterStatus == noErr else {
                    return OSStatus(eventNotHandledErr)
                }

                let shortcut = Unmanaged<GlobalRunShortcut>.fromOpaque(userData).takeUnretainedValue()
                return MainActor.assumeIsolated {
                    shortcut.handle(hotKeyID)
                }
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard handlerStatus == noErr else {
            Self.logger.error("Could not install the Control-R event handler: \(handlerStatus)")
            return
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        let registrationStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_R),
            UInt32(controlKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard registrationStatus == noErr else {
            Self.logger.error("Could not register Control-R: \(registrationStatus)")
            if let eventHandler {
                RemoveEventHandler(eventHandler)
                self.eventHandler = nil
            }
            return
        }

        Self.logger.info("Registered Control-R as the global Run shortcut")
    }

    func handle(_ hotKeyID: EventHotKeyID) -> OSStatus {
        guard hotKeyID.signature == Self.signature,
              hotKeyID.id == Self.identifier else {
            return OSStatus(eventNotHandledErr)
        }

        Self.logger.info("Received Control-R")
        action()
        return noErr
    }

    isolated deinit {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
