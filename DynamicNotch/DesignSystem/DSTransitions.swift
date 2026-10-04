//
//  DSTransitions.swift
//  DynamicNotch
//
//  Transitions du contenu de l'encoche. Zoom et flou n'existent que pendant
//  la transition : à l'état identité (repos), zoom = 1 et flou = 0.
//

import SwiftUI

private struct EmergeEffect: ViewModifier {
    let opacity: Double
    let scale: CGFloat
    let blur: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(scale, anchor: .top)
            .blur(radius: blur)
    }
}

private struct SlideEffect: ViewModifier {
    let opacity: Double
    let offsetX: CGFloat
    let blur: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(x: offsetX)
            .blur(radius: blur)
    }
}

extension AnyTransition {
    /// Le contenu émerge de l'encoche (fondu, zoom 0,92 → 1 ancré en haut,
    /// flou 6 → 0) et s'y rétracte à la sortie.
    static var emerge: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: EmergeEffect(opacity: 0, scale: 0.92, blur: 6),
                identity: EmergeEffect(opacity: 1, scale: 1, blur: 0)
            ).animation(DS.Motion.emergeIn),
            removal: .modifier(
                active: EmergeEffect(opacity: 0, scale: 0.95, blur: 4),
                identity: EmergeEffect(opacity: 1, scale: 1, blur: 0)
            ).animation(DS.Motion.emergeOut)
        )
    }

    /// Changement d'onglet : l'entrant glisse de 24 pt depuis `edge` ;
    /// le sortant s'efface (fondu + flou), sans glisser.
    static func tabSlide(from edge: Edge) -> AnyTransition {
        let offset: CGFloat = edge == .trailing ? 24 : -24
        return .asymmetric(
            insertion: .modifier(
                active: SlideEffect(opacity: 0, offsetX: offset, blur: 4),
                identity: SlideEffect(opacity: 1, offsetX: 0, blur: 0)
            ).animation(DS.Motion.expand),
            removal: .modifier(
                active: SlideEffect(opacity: 0, offsetX: 0, blur: 4),
                identity: SlideEffect(opacity: 1, offsetX: 0, blur: 0)
            ).animation(.easeIn(duration: 0.15))
        )
    }
}
