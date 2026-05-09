//
//  NotchViewController.swift
//  DynamicNotch
//

import AppKit
import Cocoa
import SwiftUI

class NotchViewController: NSHostingController<NotchView> {
    init(_ vm: NotchViewModel) {
        super.init(rootView: .init(vm: vm))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    /// Replace the default NSHostingView with one that accepts the first
    /// mouse event. Without this override, the user's first click on the
    /// closed notch (or on a page button while the notch is opened but not
    /// the key window) is consumed by the system to make the window key —
    /// the SwiftUI Button only fires on the *second* click. The fix has
    /// to live both here (view-level) and on `NotchWindow.mouseDown`
    /// (window-level focus).
    override func loadView() {
        view = FirstMouseHostingView(rootView: rootView)
    }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }
}
