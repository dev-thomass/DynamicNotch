//
//  ObservationTracking.swift
//  DynamicNotch
//
//  Équivalent d'un `sink` Combine pour les modèles `@Observable` : rappelle
//  `onChange` à chaque modification d'une propriété lue dans `read`.
//

import Foundation
import Observation

@MainActor
func observeChanges(
    _ read: @escaping @MainActor () -> Void,
    onChange: @escaping @MainActor () -> Void
) {
    withObservationTracking {
        read()
    } onChange: {
        // Appelé avant l'écriture et une seule fois : on relit au tour
        // suivant de la file principale, puis on se réabonne.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                onChange()
                observeChanges(read, onChange: onChange)
            }
        }
    }
}
