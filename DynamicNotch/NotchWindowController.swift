//
//  NotchWindowController.swift
//  DynamicNotch
//
//  Une fenêtre par écran, de taille fixe (NotchGeometry.windowSize), collée
//  en haut de l'écran et centrée sur l'encoche au pixel près. Transparente :
//  les clics hors de la coque traversent vers les fenêtres du dessous.
//

import Cocoa

class NotchWindowController: NSWindowController {
    var vm: NotchViewModel?
    weak var screen: NSScreen?

    init(screen: NSScreen, geometry: NotchGeometry, openAfterCreate: Bool) {
        self.screen = screen
        let window = NotchWindow(
            contentRect: geometry.windowFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        super.init(window: window)

        let vm = NotchViewModel(geometry: geometry)
        self.vm = vm
        contentViewController = NotchViewController(vm)
        // Cadre en coordonnées globales, déjà aligné au pixel.
        window.setFrame(geometry.windowFrame, display: true)
        window.makeKeyAndOrderFront(nil)

        guard openAfterCreate else { return }
        Task { @MainActor [weak vm] in
            vm?.notchOpen(.boot)
            // Argument Debug pour les captures : `--initial-view settings|menu|normal`.
            if let index = CommandLine.arguments.firstIndex(of: "--initial-view"),
               index + 1 < CommandLine.arguments.count
            {
                switch CommandLine.arguments[index + 1] {
                case "settings": vm?.contentType = .settings
                case "menu": vm?.contentType = .menu
                default: break
                }
            }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    func destroy() {
        vm?.destroy()
        vm = nil
        window?.close()
        contentViewController = nil
        window = nil
    }
}
