//
//  Updater.swift
//  DynamicNotch
//
//  Mises à jour automatiques via Sparkle. Le flux (appcast.xml) est publié
//  avec chaque GitHub Release par `.github/workflows/release.yml`, qui injecte
//  aussi la clé publique EdDSA (`SUPublicEDKey`) dans l'app au moment du
//  build. Une app construite localement n'a pas cette clé : l'updater reste
//  alors éteint (voir `Updater.isConfigured`).
//

import AppKit
import Combine
import Sparkle

@MainActor
final class Updater: NSObject, ObservableObject {
    static let shared = Updater()

    /// `false` pendant une vérification déjà en cours (bouton désactivé).
    @Published private(set) var canCheckForUpdates = false

    private var controller: SPUStandardUpdaterController?

    /// `true` si cette build sait se mettre à jour (build de release).
    var isAvailable: Bool {
        controller != nil
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    override private init() {
        super.init()
    }

    /// Démarre Sparkle si la build est configurée pour les mises à jour.
    /// Idempotent ; à appeler une fois au lancement.
    func start() {
        guard controller == nil else { return }
        guard Self.isConfigured(Bundle.main.infoDictionary ?? [:]) else {
            Log.app.info("updater: build sans clé de mise à jour, Sparkle désactivé")
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
        self.controller = controller
        Log.app.info("updater: Sparkle démarré")
    }

    func checkForUpdates() {
        guard let controller else { return }
        // App `.accessory` : sans activation, la fenêtre de Sparkle
        // s'ouvrirait derrière l'app au premier plan.
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    /// Une build est configurée quand elle porte un flux et une clé publique
    /// non vides — sinon Sparkle refuserait toute mise à jour.
    nonisolated static func isConfigured(_ info: [String: Any]) -> Bool {
        guard let feed = info["SUFeedURL"] as? String,
              let key = info["SUPublicEDKey"] as? String else { return false }
        return !feed.trimmingCharacters(in: .whitespaces).isEmpty
            && !key.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

extension Updater: SPUStandardUserDriverDelegate {
    /// App sans icône dans le Dock : on accepte les rappels « discrets » de
    /// Sparkle pour les vérifications planifiées.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _: Bool,
        forUpdate _: SUAppcastItem,
        state _: SPUUserUpdateState
    ) {
        Task { @MainActor in NSApp.activate() }
    }
}
