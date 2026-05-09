//
//  EventMonitors.swift
//  DynamicNotch
//
//  Created by 秋星桥 on 2024/7/7.
//

import Cocoa
import Combine

class EventMonitors {
    static let shared = EventMonitors()

    private var mouseMoveEvent: EventMonitor!
    private var mouseDownEvent: EventMonitor!
    private var mouseDraggingFileEvent: EventMonitor!
    private var optionKeyPressEvent: EventMonitor!
    private var escapeKeyEvent: EventMonitor!

    let mouseLocation: CurrentValueSubject<NSPoint, Never> = .init(.zero)
    let mouseDown: PassthroughSubject<Void, Never> = .init()
    let mouseDraggingFile: PassthroughSubject<Void, Never> = .init()
    let optionKeyPress: CurrentValueSubject<Bool, Never> = .init(false)
    /// Fires when the Escape key is pressed. Used to dismiss the opened notch.
    let escapePressed: PassthroughSubject<Void, Never> = .init()

    private init() {
        mouseMoveEvent = EventMonitor(mask: .mouseMoved) { [weak self] _ in
            guard let self else { return }
            let mouseLocation = NSEvent.mouseLocation
            self.mouseLocation.send(mouseLocation)
        }
        mouseMoveEvent.start()

        mouseDownEvent = EventMonitor(mask: .leftMouseDown) { [weak self] _ in
            guard let self else { return }
            mouseDown.send()
        }
        mouseDownEvent.start()

        mouseDraggingFileEvent = EventMonitor(mask: .leftMouseDragged) { [weak self] _ in
            guard let self else { return }
            mouseDraggingFile.send()
        }
        mouseDraggingFileEvent.start()

        optionKeyPressEvent = EventMonitor(mask: .flagsChanged) { [weak self] event in
            guard let self else { return }
            // .flagsChanged fires for every modifier (cmd/shift/ctrl/option).
            // Only push downstream when the *option* state actually changed —
            // CurrentValueSubject gives us the previous value for free.
            let isPressed = event?.modifierFlags.contains(.option) == true
            if optionKeyPress.value != isPressed {
                optionKeyPress.send(isPressed)
            }
        }
        optionKeyPressEvent.start()

        // Escape key dismisses the opened notch (a11y baseline). keyCode 53 == Escape.
        escapeKeyEvent = EventMonitor(mask: .keyDown) { [weak self] event in
            guard let self, event?.keyCode == 53 else { return }
            escapePressed.send()
        }
        escapeKeyEvent.start()
    }
}
