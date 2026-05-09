//
//  NotchWindow.swift
//  DynamicNotch
//
//  Created by 秋星桥 on 2024/7/7.
//

import Cocoa

class NotchWindow: NSWindow {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )

        isOpaque = false
        alphaValue = 1
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = NSColor.clear
        isMovable = false
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        level = .statusBar + 8 // kills ibar lol
        hasShadow = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Makes the window become key on the first click rather than swallowing
    /// it. Without this, the user's first click on the notch only activates
    /// the window — the page button / widget action only fires on the
    /// *second* click.  See `FirstMouseHostingView` below for the matching
    /// view-level acceptsFirstMouse override (both are required: the window
    /// for focus, the view for click delivery).
    override func mouseDown(with event: NSEvent) {
        if !isKeyWindow { makeKeyAndOrderFront(nil) }
        super.mouseDown(with: event)
    }
}
