//
//  DynamicNotchError.swift
//  DynamicNotch
//
//  Typed errors for the app. Replaces ad-hoc `NSError(domain:...)` usage.
//
//  Conform to `LocalizedError` so error dialogs (`NSAlert.popError`) show a
//  user-readable message via `error.localizedDescription`.
//

import Foundation

enum DynamicNotchError: LocalizedError {

    // MARK: file load / drop

    /// The system handed us an item provider but neither URL loading nor in-place
    /// file representation succeeded.
    case providerLoadFailed

    /// Loading a provider timed out (the provider never signalled completion).
    case providerLoadTimeout

    /// One or more files in a multi-file drop failed to load. The successful
    /// files are abandoned to keep the operation atomic.
    case multipleFilesFailedToLoad

    // MARK: share / AirDrop

    case sharingServiceUnavailable
    case sharingServiceCannotPerformWithFiles

    // MARK: transferable

    /// We declared `Transferable` for export only. Importing back into the app
    /// is not a supported flow.
    case importNotSupported

    // MARK: single-instance

    /// Could not acquire the global app lock.
    case singleInstanceLockFailed

    // MARK: localized strings

    var errorDescription: String? {
        switch self {
        case .providerLoadFailed:
            return "Impossible de charger le fichier depuis la source du glissement."
        case .providerLoadTimeout:
            return "Le chargement du fichier a expiré. Veuillez réessayer."
        case .multipleFilesFailedToLoad:
            return "Un ou plusieurs fichiers n'ont pas pu être chargés."
        case .sharingServiceUnavailable:
            return "Le service de partage sélectionné n'est pas disponible."
        case .sharingServiceCannotPerformWithFiles:
            return "Le service de partage ne peut pas traiter les fichiers fournis."
        case .importNotSupported:
            return "Les éléments DynamicNotch sont en lecture seule (export uniquement)."
        case .singleInstanceLockFailed:
            return "Impossible de démarrer DynamicNotch — une autre instance est peut-être déjà ouverte."
        }
    }
}
