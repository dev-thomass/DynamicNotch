//
//  Ext+NSAlert.swift
//  DynamicNotch
//
//  Created by 秋星桥 on 2024/7/9.
//

import Cocoa

extension NSAlert {
    static func popError(_ error: String) {
        let alert = NSAlert()
        alert.messageText = "Erreur"
        alert.alertStyle = .critical
        alert.informativeText = error
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    static func popRestart(_ error: String, completion: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Redémarrage nécessaire"
        alert.alertStyle = .critical
        alert.informativeText = error
        alert.addButton(withTitle: "Quitter")
        alert.addButton(withTitle: "Plus tard")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            completion()
        }
    }

    static func popError(_ error: Error) {
        popError(error.localizedDescription)
    }

    /// Show a confirmation dialog and return whether the user confirmed.
    ///
    /// - Parameters:
    ///   - title: bold message text shown at the top.
    ///   - message: secondary informative text.
    ///   - confirm: title for the affirmative button (e.g. "Delete").
    ///   - destructive: when `true`, the alert is styled as a critical warning
    ///     and "Cancel" is the default (return) button. Use this for any action
    ///     that loses user data (Clear, Quit-with-pending-files, ...).
    /// - Returns: `true` if the user pressed the confirm button.
    @discardableResult
    static func popConfirm(
        title: String,
        message: String,
        confirm: String,
        destructive: Bool = false
    ) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = destructive ? .critical : .warning

        let confirmButton = alert.addButton(withTitle: confirm)
        let cancelButton = alert.addButton(withTitle: "Annuler")

        // For destructive actions, make Cancel the default (Return-key) action
        // so a stray keystroke doesn't trigger data loss.
        if destructive {
            confirmButton.keyEquivalent = ""
            cancelButton.keyEquivalent = "\r"
            confirmButton.hasDestructiveAction = true
        }

        return alert.runModal() == .alertFirstButtonReturn
    }
}
