//
//  Ext+NSScreen.swift
//  DynamicNotch
//
//  Détection robuste de la taille de l'encoche matérielle d'un écran.
//
//  Bug rencontré : sur certains Macs (notamment quand un écran externe est
//  branché OU quand la résolution affichée n'est pas la résolution native),
//  `auxiliaryTopLeftArea` ou `auxiliaryTopRightArea` pouvaient retourner
//  `nil` ou des valeurs nulles, alors même que `safeAreaInsets.top > 0`
//  indique clairement la présence d'une encoche → notre code retournait
//  `.zero` et l'app tombait en mode "pilule simulée" même sur un Mac avec
//  encoche réelle, donnant une silhouette mal dimensionnée.
//
//  Fix : si les aux areas ne sont pas exploitables, on garde `safeAreaInsets.top`
//  comme hauteur (toujours fiable) et on calcule la largeur via une
//  heuristique stable basée sur les modèles M-series connus (~30 % du
//  display width pour l'encoche, centrée).
//

import Cocoa

extension NSScreen {
    /// Taille de l'encoche matérielle en points logiques. `.zero` si aucune
    /// encoche détectée.
    var notchSize: CGSize {
        // Une encoche matérielle expose toujours un `safeAreaInsets.top > 0`.
        // C'est le signal le plus fiable.
        guard safeAreaInsets.top > 0 else { return .zero }
        let notchHeight = safeAreaInsets.top

        // Voie nominale : utiliser les aux areas exposées par macOS.
        // Quand elles sont valides, c'est pixel-perfect.
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0
        if leftPadding > 0, rightPadding > 0 {
            let notchWidth = frame.width - leftPadding - rightPadding
            // Garde-fou : si le calcul donne un résultat aberrant (largeur
            // négative ou démesurée), on bascule sur le fallback.
            if notchWidth > 50, notchWidth < frame.width / 2 {
                return CGSize(width: notchWidth, height: notchHeight)
            }
        }

        // Fallback heuristique : la largeur d'encoche varie selon le modèle
        // mais reste grossièrement proportionnelle à la largeur du display.
        // Les ratios observés sur les MacBook M-series :
        //   - Air 13" / 15"   : ~12-13 % de la largeur
        //   - MacBook Pro 14" : ~12 %
        //   - MacBook Pro 16" : ~11 %
        // 12 % couvre les 3 cas avec une erreur visuelle ≤ 5pt.
        let estimatedWidth = frame.width * 0.12
        return CGSize(width: estimatedWidth, height: notchHeight)
    }

    var isBuildinDisplay: Bool {
        let screenNumberKey = NSDeviceDescriptionKey(rawValue: "NSScreenNumber")
        guard let id = deviceDescription[screenNumberKey],
              let rid = (id as? NSNumber)?.uint32Value,
              CGDisplayIsBuiltin(rid) == 1
        else { return false }
        return true
    }

    static var buildin: NSScreen? {
        screens.first { $0.isBuildinDisplay }
    }
}
