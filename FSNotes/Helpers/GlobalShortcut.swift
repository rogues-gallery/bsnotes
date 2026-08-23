//
//  GlobalShortcut.swift
//  FSNotes
//

import AppKit
import Carbon.HIToolbox

final class GlobalShortcut: Hashable {
    let keyCode: UInt
    let modifierFlags: UInt

    init(keyCode: UInt, modifierFlags: UInt) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }

    static func == (lhs: GlobalShortcut, rhs: GlobalShortcut) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifierFlags == rhs.modifierFlags
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifierFlags)
    }

    fileprivate var carbonModifierFlags: UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: modifierFlags)
        var result: UInt32 = 0

        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }

        return result
    }

    fileprivate var displayString: String {
        let flags = NSEvent.ModifierFlags(rawValue: modifierFlags)
        var result = ""

        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }

        return result + Self.keyNames[keyCode, default: "Key \(keyCode)"]
    }

    private static let keyNames: [UInt: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "−", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`",
        51: "⌫", 53: "⎋", 65: ".", 67: "*", 69: "+", 71: "Clear", 75: "/",
        76: "⌤", 78: "−", 81: "=", 82: "0", 83: "1", 84: "2", 85: "3",
        86: "4", 87: "5", 88: "6", 89: "7", 91: "8", 92: "9", 96: "F5",
        97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12",
        113: "F15", 114: "Help", 115: "↖", 116: "⇞", 117: "⌦", 118: "F4",
        119: "↘", 120: "F2", 121: "⇟", 122: "F1", 123: "←", 124: "→",
        125: "↓", 126: "↑"
    ]
}

final class GlobalShortcutMonitor {
    private struct Registration {
        let identifier: UInt32
        let hotKey: EventHotKeyRef
        let action: () -> Void
    }

    private static let instance = GlobalShortcutMonitor()
    private static let signature: OSType = 0x46534E54 // FSNT

    private var eventHandler: EventHandlerRef?
    private var registrations: [GlobalShortcut: Registration] = [:]
    private var shortcutsByIdentifier: [UInt32: GlobalShortcut] = [:]
    private var nextIdentifier: UInt32 = 1

    static func shared() -> GlobalShortcutMonitor { instance }

    private init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }

                let monitor = Unmanaged<GlobalShortcutMonitor>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                monitor.performAction(identifier: hotKeyID.id)
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    deinit {
        unregisterAllShortcuts()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    @discardableResult
    func register(_ shortcut: GlobalShortcut?, withAction action: @escaping () -> Void) -> Bool {
        guard let shortcut, registrations[shortcut] == nil else { return false }

        let identifier = nextIdentifier
        nextIdentifier &+= 1
        var hotKey: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )

        guard status == noErr, let hotKey else { return false }
        registrations[shortcut] = Registration(identifier: identifier, hotKey: hotKey, action: action)
        shortcutsByIdentifier[identifier] = shortcut
        return true
    }

    func unregisterShortcut(_ shortcut: GlobalShortcut?) {
        guard let shortcut, let registration = registrations.removeValue(forKey: shortcut) else { return }
        UnregisterEventHotKey(registration.hotKey)
        shortcutsByIdentifier.removeValue(forKey: registration.identifier)
    }

    func unregisterAllShortcuts() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.hotKey)
        }
        registrations.removeAll()
        shortcutsByIdentifier.removeAll()
    }

    private func performAction(identifier: UInt32) {
        guard let shortcut = shortcutsByIdentifier[identifier],
              let action = registrations[shortcut]?.action else { return }
        DispatchQueue.main.async(execute: action)
    }
}

final class ShortcutValidator {
    var allowAnyShortcutWithOptionModifier = false
}

@objc(ShortcutRecorderView)
final class ShortcutRecorderView: NSView {
    var shortcutValue: GlobalShortcut! {
        didSet { updateTitle() }
    }
    let shortcutValidator = ShortcutValidator()
    var shortcutValueChange: ((ShortcutRecorderView) -> Void)?

    private let button = NSButton()
    private var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        updateTitle()
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            window?.makeFirstResponder(nil)
            return
        }

        if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
            shortcutValue = nil
            shortcutValueChange?(self)
            window?.makeFirstResponder(nil)
            return
        }

        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let hasRequiredModifier = flags.contains(.command)
            || flags.contains(.control)
            || (shortcutValidator.allowAnyShortcutWithOptionModifier && flags.contains(.option))
        guard hasRequiredModifier else {
            NSSound.beep()
            return
        }

        shortcutValue = GlobalShortcut(
            keyCode: UInt(event.keyCode),
            modifierFlags: flags.rawValue
        )
        shortcutValueChange?(self)
        window?.makeFirstResponder(nil)
    }

    private func configure() {
        button.title = "Record Shortcut"
        button.bezelStyle = .rounded
        button.target = self
        button.action = #selector(beginRecording)
        button.autoresizingMask = [.width, .height]
        button.frame = bounds
        addSubview(button)
    }

    @objc private func beginRecording() {
        isRecording = true
        button.title = "Type Shortcut"
        window?.makeFirstResponder(self)
    }

    private func updateTitle() {
        button.title = isRecording ? "Type Shortcut" : (shortcutValue?.displayString ?? "Record Shortcut")
    }
}
