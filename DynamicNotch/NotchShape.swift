//
//  NotchShape.swift
//  DynamicNotch
//
//  Silhouette de l'encoche matérielle, dessinée comme un seul `Shape` SwiftUI.
//
//  Remplace l'ancien `notchBackgroundMaskGroup` qui composait la forme à
//  partir de plusieurs `Rectangle` + overlays + offsets manuels — combinaison
//  fragile qui pouvait laisser un petit carré parasite en haut à gauche
//  pendant les transitions d'animation (le mask et les overlays se
//  désynchronisaient d'une frame). Avec un Path unique, le rendu est
//  atomique et garanti pixel-cohérent.
//
//  Géométrie :
//
//      0,0 ────────────────────── w,0     ← bord du bezel (top)
//          ╲                    ╱         ← coins concaves outer
//           r,r            w-r,r          ← coins du body interne
//             │            │
//             │            │              ← parois latérales du body
//             │            │
//           r,h-r       w-r,h-r
//             ╲          ╱                ← coins arrondis bottom (convexe extérieur)
//              2r,h──w-2r,h               ← bord inférieur
//
//  Le `rect.width` total = `notchSize.width + 2·cornerRadius`. Les courbes
//  concaves "outer" occupent les `r` premiers et derniers pt à gauche/droite.
//

import SwiftUI

struct NotchShape: Shape {
    /// Rayon des coins (concaves en haut, arrondis convexes en bas).
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = cornerRadius
        let w = rect.width
        let h = rect.height

        // Coin haut-gauche du bezel (point de départ).
        p.move(to: CGPoint(x: 0, y: 0))

        // Courbe concave outer : courbe vers la droite-bas pour rejoindre
        // le coin interne haut-gauche du body. Le control point en (r,0)
        // bulge la courbe vers le HAUT-DROITE (extérieur de la silhouette),
        // ce qui crée la sensation d'une encoche dont les bords supérieurs
        // se fondent dans le bezel.
        p.addQuadCurve(
            to: CGPoint(x: r, y: r),
            control: CGPoint(x: r, y: 0)
        )

        // Paroi gauche du body.
        p.addLine(to: CGPoint(x: r, y: h - r))

        // Coin bottom-left arrondi (convexe extérieur). Control en (r, h)
        // → bulge vers le BAS-GAUCHE qui est extérieur à la silhouette.
        p.addQuadCurve(
            to: CGPoint(x: 2 * r, y: h),
            control: CGPoint(x: r, y: h)
        )

        // Bord inférieur du body.
        p.addLine(to: CGPoint(x: w - 2 * r, y: h))

        // Coin bottom-right arrondi (convexe extérieur).
        p.addQuadCurve(
            to: CGPoint(x: w - r, y: h - r),
            control: CGPoint(x: w - r, y: h)
        )

        // Paroi droite du body.
        p.addLine(to: CGPoint(x: w - r, y: r))

        // Courbe concave outer haut-droite, retour au bezel.
        p.addQuadCurve(
            to: CGPoint(x: w, y: 0),
            control: CGPoint(x: w - r, y: 0)
        )

        // Fermeture : ligne droite le long du bezel (de w,0 à 0,0).
        p.closeSubpath()
        return p
    }
}
