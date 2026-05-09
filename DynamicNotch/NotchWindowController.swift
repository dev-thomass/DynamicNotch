//
//  NotchWindowController.swift
//  DynamicNotch
//
//  Created by 秋星桥 on 2024/7/7.
//

import Cocoa

/// Hosting window height. Must be ≥ the tallest opened-panel size produced by
/// `NotchViewModel.notchOpenedSize` (currently Settings = 560pt) plus headroom
/// for the closed→opened scale animation. The window itself is borderless and
/// transparent, so being oversized has no visual cost — the SwiftUI content
/// only paints the actual notch shell.
private let notchHeight: CGFloat = 620

class NotchWindowController: NSWindowController {
    var vm: NotchViewModel?
    weak var screen: NSScreen?

    /// Whether the notch should auto-open right after creation. Must be passed
    /// at construction time; the init reads it synchronously to schedule the
    /// boot animation.
    let openAfterCreate: Bool

    init(window: NSWindow, screen: NSScreen, openAfterCreate: Bool) {
        self.screen = screen
        self.openAfterCreate = openAfterCreate

        super.init(window: window)

        var notchSize = screen.notchSize

        let vm = NotchViewModel(inset: notchSize == .zero ? 0 : -4)
        self.vm = vm
        contentViewController = NotchViewController(vm)

        if notchSize == .zero {
            notchSize = .init(width: 150, height: 28)
        }
        vm.deviceNotchRect = CGRect(
            x: screen.frame.origin.x + (screen.frame.width - notchSize.width) / 2,
            y: screen.frame.origin.y + screen.frame.height - notchSize.height,
            width: notchSize.width,
            height: notchSize.height
        )

        // Set screenRect synchronously so the first render lays out at the
        // correct position. The previous 100 ms asyncAfter caused a one-frame
        // flicker where notchOpenedRect was computed against `.zero`.
        vm.screenRect = screen.frame

        window.makeKeyAndOrderFront(nil)

        // The boot-open animation can still wait for the next runloop tick so
        // SwiftUI has time to install the view hierarchy before we drive a
        // state change.
        if openAfterCreate {
            DispatchQueue.main.async { [weak vm] in
                vm?.notchOpen(.boot)
                // Debug-only launch arg used for screenshot capture in CI/demo.
                // Pass `--initial-view settings|menu|normal` to land in a
                // specific tab right after boot. No effect in normal usage.
                if let idx = CommandLine.arguments.firstIndex(of: "--initial-view"),
                   idx + 1 < CommandLine.arguments.count
                {
                    switch CommandLine.arguments[idx + 1] {
                    case "settings": vm?.contentType = .settings
                    case "menu":     vm?.contentType = .menu
                    case "normal":   vm?.contentType = .normal
                    default:         break
                    }
                }
            }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    convenience init(screen: NSScreen, openAfterCreate: Bool = false) {
        let window = NotchWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        self.init(window: window, screen: screen, openAfterCreate: openAfterCreate)

        let topRect = CGRect(
            x: screen.frame.origin.x,
            y: screen.frame.origin.y + screen.frame.height - notchHeight,
            width: screen.frame.width,
            height: notchHeight
        )
        window.setFrameOrigin(topRect.origin)
        window.setContentSize(topRect.size)
    }

    deinit {
        destroy()
    }

    func destroy() {
        vm?.destroy()
        vm = nil
        window?.close()
        contentViewController = nil
        window = nil
    }
}
