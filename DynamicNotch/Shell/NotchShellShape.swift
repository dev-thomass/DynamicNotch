//
//  NotchShellShape.swift
//  DynamicNotch
//
//  Silhouette unique de la coque, dessinée dans un canevas de taille fixe (la
//  fenêtre). Seule la géométrie du tracé est animée : aucune animation de
//  frame ni de mise à l'échelle, donc des bords nets à chaque image.
//
//      (left − tr, 0) ────────────────────────── (right + tr, 0)   ← bord de l'écran
//             ╲ oreille concave        oreille ╱
//          (left, tr)                    (right, tr)
//              │                             │
//          (left, h − br)              (right, h − br)
//              ╰── coin bas ────── coin bas ──╯
//

import SwiftUI

struct NotchShellShape: Shape {
    /// Centre horizontal de l'encoche dans le canevas (non animé).
    var centerX: CGFloat
    /// Largeur du corps, oreilles exclues.
    var bodyWidth: CGFloat
    var bodyHeight: CGFloat
    /// Rayon des oreilles concaves du haut ; 0 pour une pilule.
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    /// Coefficient de Bézier d'un quart de cercle (1 − 0,552).
    private static let k: CGFloat = 0.448

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(bodyWidth, bodyHeight), .init(topRadius, bottomRadius)) }
        set {
            bodyWidth = newValue.first.first
            bodyHeight = newValue.first.second
            topRadius = newValue.second.first
            bottomRadius = newValue.second.second
        }
    }

    func path(in _: CGRect) -> Path {
        let width = max(0, bodyWidth)
        let height = max(0, bodyHeight)
        let tr = max(0, min(topRadius, height / 2))
        let br = max(0, min(bottomRadius, height - tr, width / 2))
        let left = centerX - width / 2
        let right = centerX + width / 2
        let k = Self.k

        var p = Path()
        p.move(to: CGPoint(x: left - tr, y: 0))
        p.addCurve(
            to: CGPoint(x: left, y: tr),
            control1: CGPoint(x: left - tr * k, y: 0),
            control2: CGPoint(x: left, y: tr * k)
        )
        p.addLine(to: CGPoint(x: left, y: height - br))
        p.addCurve(
            to: CGPoint(x: left + br, y: height),
            control1: CGPoint(x: left, y: height - br * k),
            control2: CGPoint(x: left + br * k, y: height)
        )
        p.addLine(to: CGPoint(x: right - br, y: height))
        p.addCurve(
            to: CGPoint(x: right, y: height - br),
            control1: CGPoint(x: right - br * k, y: height),
            control2: CGPoint(x: right, y: height - br * k)
        )
        p.addLine(to: CGPoint(x: right, y: tr))
        p.addCurve(
            to: CGPoint(x: right + tr, y: 0),
            control1: CGPoint(x: right, y: tr * k),
            control2: CGPoint(x: right + tr * k, y: 0)
        )
        p.closeSubpath()
        return p
    }
}
