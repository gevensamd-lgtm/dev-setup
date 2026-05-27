// upload-hotkey — Cmd+Shift+V global. Sube clipboard + auto-paste.
// Compile: swiftc upload-hotkey.swift -o upload-hotkey -framework Carbon -framework Cocoa

import Cocoa
import Carbon
import CoreGraphics

let UPLOAD_SCRIPT = "/Users/gevensa/.local/bin/upload-from-clipboard"

func sendCmdV() {
    let src = CGEventSource(stateID: .combinedSessionState)
    let vDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
    let vUp   = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
    vDown?.flags = .maskCommand
    vUp?.flags   = .maskCommand
    vDown?.post(tap: .cghidEventTap)
    vUp?.post(tap: .cghidEventTap)
}

func runUploadAndPaste() {
    DispatchQueue.global().async {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments  = [UPLOAD_SCRIPT]
        do {
            try task.run()
            task.waitUntilExit()
            DispatchQueue.main.async {
                sendCmdV()
            }
        } catch {
            NSLog("upload-hotkey: failed: \(error)")
        }
    }
}

let signature: OSType = OSType(0x55504C44) // "UPLD"
var hotKeyRef: EventHotKeyRef?
var hotKeyID = EventHotKeyID(signature: signature, id: 1)

let keyCode: UInt32 = 9                              // V
let modifiers: UInt32 = UInt32(cmdKey | shiftKey)    // Cmd+Shift

let regStatus = RegisterEventHotKey(
    keyCode, modifiers, hotKeyID,
    GetApplicationEventTarget(), 0, &hotKeyRef
)

guard regStatus == noErr else {
    NSLog("upload-hotkey: RegisterEventHotKey failed: \(regStatus)")
    exit(1)
}

NSLog("upload-hotkey: registered Cmd+Shift+V")

var eventType = EventTypeSpec(
    eventClass: OSType(kEventClassKeyboard),
    eventKind:  UInt32(kEventHotKeyPressed)
)

InstallEventHandler(
    GetApplicationEventTarget(),
    { (_, _, _) -> OSStatus in
        runUploadAndPaste()
        return noErr
    },
    1, &eventType, nil, nil
)

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
