//
//  AccessibilityHelper.swift
//  DynamicNotch
//
//  Helpers pour la permission Accessibility, requise par
//  `CGEvent.tapCreate` quand on veut CONSOMMER les touches média (sinon le
//  HUD natif macOS s'affiche en parallèle du nôtre).
//

import ApplicationServices
import Foundation

enum AccessibilityHelper {

    /// `true` si l'app a la permission Accessibility, sinon `false`.
    /// N'affiche AUCUN dialog — utilisé pour rendre l'UI Settings
    /// (toggle activable / non).
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Demande la permission. Si pas encore accordée, le système ouvre
    /// automatiquement la fenêtre de réglage (ou un dialogue d'invite).
    /// Retourne `true` si déjà accordée à l'instant T, `false` sinon —
    /// l'utilisateur peut accorder dans les secondes qui suivent.
    @discardableResult
    static func requestAccess() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeRetainedValue() as String
        let opts = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Ouvre directement le panneau Réglages → Confidentialité →
    /// Accessibilité. Pratique si l'utilisateur a refusé le dialog.
    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

import AppKit
